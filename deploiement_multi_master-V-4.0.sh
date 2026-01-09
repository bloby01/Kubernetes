#!/bin/sh
set -e
#												FONCTIONNEL !
#
# vm de bases: https://drive.google.com/file/d/1bj-_BYa25Ms36Qy1aEb82C29UKZ3aTlD/view?usp=sharing
#
#   Version script		: 4.0
#   Deploiement sur Rocky Linux : 10
#   Version kubelet		: 1.34
#   Version Containerd  : 2.2.0
#   Version RunC 		: 1.4.0
#   Version CNI-Plugin	: 1.9.0
#   Version calico		: 3.31.2
#   Version minimal Kubelet	: 1.29
#
#   Script de déploiment kubernetes en multi-masters avec LB HAPROXY sur virtualbox
#   By ste.cmc.merle@gmail.com
#
# Script destiné à faciliter le déploiement de cluster kubernetes en multi-master
# Il est à exécuter dans le cadre d'une formation.
#
#
#
#################################################################################
#                                                                               #
#                       LABS  Kubernetes                                        #
#       INTERNET																#
#            |																	#
#  Client kubectl -|    														#
#            192.168.x.x/xx														#
#            	  LB NAT			    	      		                        #
#			172.21.0.100/24														#
#			       |															#				
#                  |    master1 (172.21.0.101/24)                               #
#                  |      |      master2 (172.21.0.102/24)                      #
#                  |      |       |     master3 (172.21.0.103/24)               #
#                  |      |       |     |                                       #
#                  |      |       |     |                                       #
#                  |      _________________                                     #
#      			   |_____|  switch  interne|           			                #
#		                 |   172.21.0.0/24 |									#
#                        |_________________|                                    #
#                         |     |      |                                        #
#                         |     |      |                                        #
#     (172.21.0.104/24)worker1  |      |                                        #
#     		(172.21.0.105/24)worker2   |                                        #
#             	 (172.21.0.106/24)worker3                                       #
#                                                                               #
#                                                                               #
#                                                                               #			
#################################################################################
#                                                                               #
#                          Features                                             #
#                                                                               #
#################################################################################
#                                                                               #
# - Le système sur lequel s'exécute ce script doit être un Rocky Linux 10       #
# - Le compte root doit etre utilisé pour exécuter ce Script                    #
# - Le script requière :		        										#
#	*  Hyperviseur virtualbox: Le cluster fonctionne dans un réseau privé NAT   #
#           sans dhcp sur le réseau k8s   					     				#  
#	*  Le loadBalancer est externe au cluster, il fonctionne sur réseau k8s 	#
#       	- L'adresse IP du loadbalancer    :   172.21.0.100/24          		#
#   	*  Les adresses/noms des noeuds sont attribuées	en statiques			#
#			La résolution de nom est réaliser via fichier hosts					#
# - Le réseau overlay est gérer par VxLAN à l'aide de Calico                    #
# - Les systèmes sont synchronisés sur le serveur de temps zone Europe/Paris    #
# - Le LABS est établie avec un maximum de 3 noeuds masters & 3 noeuds workers  #
# - L'API est joignable par le loadBalancer sur l'adresse 172.21.0.100:6443     #
# - Firewalld en trusted
#################################################################################


###########################################################################################
#                                                                               	  #
#                      Déclaration des variables                                	  #
#                                                                               	  #
###########################################################################################
#
export numetape=0
export NBR=0
export appmaster="bash-completion wget tar bind-utils nfs-utils kubelet iproute-tc kubelet kubeadm kubectl cri-tools kubernetes-cni openssl"
export appworker="bash-completion wget tar bind-utils nfs-utils kubelet iproute-tc kubeadm kubectl cri-tools kubernetes-cni openssl"
export appHAProxy="bash-completion wget haproxy nfs-utils bind-utils iproute-tc policycoreutils-python-utils tar"
export VersionContainerD="2.2.0"
export VersionRunC="1.4.0"
export VersionCNI="1.9.0"
export VersionCalico="3.31.2"
#                                                                               	  #
###########################################################################################
#                                                                               	  #
#                      Déclaration des fonctions                                	  #
#                                                                               	  #
###########################################################################################
# 
#Fonction de vérification des étapes
#

verif(){
	numetape=`expr ${numetape} + 1 `
	  if [ "${vrai}" -eq "0" ]; then
	    echo "Machine: ${node}${x}-k8s.mon.dom - ${nom} - OK"
	  else
	    echo "Erreur sur Machine: ${node}${x}-k8s.mon.dom - ${nom} - OUPSSS "
	    exit 0
	  fi
}
#################################################
# 

#Fonction de question sur le choix du réseau à utiliser en CNI
#
ChoixReseau(){
	Reseau=non
	until [ ${Reseau} = "calico" -o ${Reseau} = "flannel" ]
	do
	echo -n "Quelle version de support CNI voulez-vous utiliser ? [ calico  /  flannel ] :"
	read Reseau
	done
	vrai="0"
	nom="Choix du addon réseau: ${Reseau} "
}
#################################################
# 

#Fonction de contrôle du SELinux
#
#SELinux(){
#	setenforce 0 && \
#	sed -i 's/^SELINUX=enforcing$/SELINUX=disabled/' /etc/selinux/config
#	grubby --update-kernel ALL --args selinux=0
#}
#################################################
# 

#Fonction d'installation du repo pour Kubernetes
#
repok8s(){
cat <<EOF | tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/${Version_k8s}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/${Version_k8s}/rpm/repodata/repomd.xml.key
EOF
}
#################################################
# 

# Fonction d'installation de containerd en derniere version stable
#
#################################################
containerd(){
wget  https://github.com/containerd/containerd/releases/download/v${VersionContainerD}/containerd-${VersionContainerD}-linux-amd64.tar.gz
if [ -f containerd-${VersionContainerD}-linux-amd64.tar.gz ]
then
	tar Cxzf /usr/local/ containerd-${VersionContainerD}-linux-amd64.tar.gz
else
	scp root@master1-k8s.mon.dom:Kubernetes/containerd-${VersionContainerD}-linux-amd64.tar.gz .
	tar Cxzf /usr/local/ containerd-${VersionContainerD}-linux-amd64.tar.gz
fi
mkdir -p /usr/local/lib/systemd/system/
cat <<EOF | tee /usr/local/lib/systemd/system/containerd.service
# Copyright The containerd Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

[Unit]
Description=containerd container runtime
Documentation=https://containerd.io
After=network.target local-fs.target

[Service]
ExecStartPre=-/sbin/modprobe overlay
ExecStart=/usr/local/bin/containerd

Type=notify
Delegate=yes
KillMode=process
Restart=always
RestartSec=5
# Having non-zero Limit*s causes performance problems due to accounting overhead
# in the kernel. We recommend using cgroups to do container-local accounting.
LimitNPROC=infinity
LimitCORE=infinity
LimitNOFILE=infinity
# Comment TasksMax if your systemd version does not supports it.
# Only systemd 226 and above support this version.
TasksMax=infinity
OOMScoreAdjust=-999

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload && \
systemctl enable --now containerd && \
if [ -f runc.amd64 ]
then
	install -m  755 runc.amd64  /usr/local/bin/runc
else
	scp root@master1-k8s.mon.dom:Kubernetes/runc.amd64 . && \
	install -m  755 runc.amd64  /usr/local/bin/runc
fi

if [ -f cni-plugins-linux-amd64-v${VersionCNI}.tgz ]
then
	mkdir -p /opt/cni/bin && \
	tar Cxzf /opt/cni/bin/ cni-plugins-linux-amd64-v${VersionCNI}.tgz
else
	scp root@master1-k8s.mon.dom:Kubernetes/cni-plugins-linux-amd64-v${VersionCNI}.tgz . && \
	mkdir -p /opt/cni/bin && \
	tar Cxzf /opt/cni/bin/ cni-plugins-linux-amd64-v${VersionCNI}.tgz
fi
}

#################################################
# 
# Fonction  de configuration du swap à off
#
#################################################
Swap(){
swapoff   -a && \
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
}
####################################################
#
# Fonction de configuration du module bridge
#
####################################################
moduleBr(){
modprobe  br_netfilter && \
cat <<EOF | tee /etc/rc.modules
modprobe  br_netfilter
EOF
chmod  +x  /etc/rc.modules && \
sysctl   -w net.bridge.bridge-nf-call-iptables=1 && \
sysctl   -w net.bridge.bridge-nf-call-ip6tables=1 && \
sysctl -w net.ipv4.ip_forward=1 && \
cat <<EOF | tee /etc/sysctl.conf
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
net.ipv4.ip_forward=1
EOF
}
#######################################################
#
# Fonction de serveur de temps
#
#######################################################
temps(){
timedatectl set-timezone "Europe/Paris" && \
timedatectl set-ntp true && \
systemctl restart chronyd && \
chronyc tracking 
}
########################################################
#
# Fonction de création des clés pour ssh-copy-id
#
########################################################
CopyIdRootSrvSupp(){
ssh-copy-id -i ~/.ssh/id_rsa.pub root@master1-k8s.mon.dom
}
#########################################################
#
# Fonction de création des clés pour ssh-copy-id
#
#########################################################
CopyIdRoot(){
ssh-keygen -b 4096 -t rsa -f ~/.ssh/id_rsa -P "" && \
ssh-copy-id -i ~/.ssh/id_rsa.pub root@master1-k8s.mon.dom
}
###########################################################
#
# Fonction de création des clés pour ssh-copy-id
#
###########################################################
CopyIdLB(){
ssh-keygen -b 4096 -t rsa -f ~/.ssh/id_rsa -P "" && \
ssh-copy-id -i ~/.ssh/id_rsa.pub root@loadBalancer-k8s.mon.dom
}
##############################################################
#
# Fonction de récupération du token et sha256 de cacert
#
##############################################################
RecupToken(){
alias master1="ssh root@master1-k8s.mon.dom" && \
scp root@master1-k8s.mon.dom:noeudsupplementaires.txt ~/. && \
if [ -d ~/.kube ]
	then
	scp root@master1-k8s.mon.dom:/etc/kubernetes/admin.conf ~/.kube/config
else
	mkdir ~/.kube
	scp root@master1-k8s.mon.dom:/etc/kubernetes/admin.conf ~/.kube/config
fi && \
export KUBECONFIG=~/.kube/config && \
export token=$(grep token ~/noeudsupplementaires.txt | head -1 | cut -f 4 -d " ") && \
export CertsKey=$(grep certificate-key ~/noeudsupplementaires.txt | head -1) && \
export tokencaworker=`master1 openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //'` && \
export tokensha=`master1 openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //'`
}
#############################################################
# 
# Démarrage du service kubelet
#
#############################################################
StartServiceKubelet(){
mkdir -p /var/lib/kubelet/ && \
cat <<EOF | tee /var/lib/kubelet/config.yaml
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
EOF
mkdir -p /etc/kubernetes/ && \
cat <<EOF | tee /var/lib/kubelet/proxy.yaml
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration
mode: "iptables" # ou "ipvs" selon votre choix
#featureGates:
#  SupportIPVSProxyMode: true # Si vous utilisez le mode "ipvs"
EOF
systemctl daemon-reload && \
systemctl enable --now kubelet
}
################################################################
#
# configuration du service haproxy
#
################################################################
ConfHaProxy(){
cat <<EOF | tee /etc/haproxy/haproxy.cfg
global
    log         127.0.0.1 local2
    chroot      /var/lib/haproxy
    pidfile     /var/run/haproxy.pid
    maxconn     4000
    user        haproxy
    group       haproxy
    daemon
    stats socket /var/lib/haproxy/stats
    ssl-default-bind-ciphers PROFILE=SYSTEM
    ssl-default-server-ciphers PROFILE=SYSTEM
defaults
    mode                    http
    log                     global
    option                  httplog
    option                  dontlognull
    option http-server-close
#    option forwardfor       except 127.0.0.0/8
    option                  redispatch
    retries                 3
    timeout http-request    10s
    timeout queue           1m
    timeout connect         10s
    timeout client          1m
    timeout server          1m
    timeout http-keep-alive 10s
    timeout check           10s
    maxconn                 3000
frontend main
    bind *:5000
    acl url_static       path_beg       -i /static /images /javascript /stylesheets
    acl url_static       path_end       -i .jpg .gif .png .css .js
    use_backend static          if url_static
    default_backend             app
backend static
    balance     roundrobin
    server      static 127.0.0.1:4331 check
backend app
    balance     roundrobin
    server  app1 127.0.0.1:5001 check
    server  app2 127.0.0.1:5002 check
    server  app3 127.0.0.1:5003 check
    server  app4 127.0.0.1:5004 check
frontend kubernetes-frontend
    bind loadBalancer-k8s.mon.dom:6443
    mode tcp
    option tcplog
    default_backend kubernetes-backend
backend kubernetes-backend
    mode tcp
    option tcp-check
    balance roundrobin
#    server noeud1 master1-k8s.mon.dom:6443 check fall 3 rise 2
#    server noeud2 master2-k8s.mon.dom:6443 check fall 3 rise 2
#    server noeud3 master3-k8s.mon.dom:6443 check fall 3 rise 2
EOF
}
#################################################
# 
# Ouverture du passage des flux IN sur les interfaces réseaux
#
#################################################
parefeuLB(){
firewall-cmd  --set-default-zone trusted && \
firewall-cmd --add-interface=lo --zone=trusted --permanent && \
firewall-cmd --reload
}
#################################################
# 
# Ouverture du passage des flux IN sur les interfaces réseaux
#
#################################################
parefeuNoeudsMaster(){
firewall-cmd  --set-default-zone trusted && \
firewall-cmd --add-interface=lo --zone=trusted --permanent && \
firewall-cmd --reload
}

parefeuNoeudsWorker(){
firewall-cmd  --set-default-zone trusted && \
firewall-cmd --add-interface=lo --zone=trusted --permanent && \
firewall-cmd --reload
}
#################################################
# 
# fonction de configuration NFS
#
#################################################
nfs(){
if [ -b /dev/sdb ]
	then
	echo "le périphérique disque sdb est présent"
	else
		echo "Pas de disque additionnel /dev/sdb pour le volume lvm de NFS, faire valider pour sortir et ajouter un disque à la machine ..."
		read tt
		exit 1
fi
if [ -b /dev/sdb ]
	then
	pvcreate /dev/sdb
	vgcreate dataVG /dev/sdb
	lvcreate -n volume1 -l 100%FREE dataVG
	mkfs -t xfs /dev/dataVG/volume1
 	mkdir -p /srv/nfs/data
  	chown -R nobody: /srv/nfs/data
	echo "/dev/dataVG/volume1 /srv/nfs/data xfs defaults 0 0" >> /etc/fstab
 	systemctl daemon-reload
  	mount /srv/nfs/data
cat <<EOF | tee /etc/exports
/srv/nfs/data	*(rw,sync,no_subtree_check,no_root_squash,no_all_squash,insecure)
EOF
     	systemctl enable --now nfs-server
      	exportfs -rav
fi
}
#################################################
# 
# Fonction de configuration /etc/hosts
#
#################################################
mkhosts () {
cat <<EOF | tee /etc/hosts
127.0.0.1 localhost localhost.localdomain
172.21.0.100 loadbalancer-k8s.mon.dom
172.21.0.101 master1-k8s.mon.dom traefik.mon.dom w1.mon.dom  w2.mon.dom
172.21.0.102 master2-k8s.mon.dom
172.21.0.103 master3-k8s.mon.dom
172.21.0.104 worker1-k8s.mon.dom
172.21.0.105 worker2-k8s.mon.dom
172.21.0.106 worker3-k8s.mon.dom
EOF
}
#&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&
#                             Debut de la séquence d'Installation                                 #
#                                                                                                 #
#&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&



############################################################################################
#                                                                                          #
#                       Paramètres communs LB HAProxy, master et worker                    #
#                                                                                          #
############################################################################################
clear
until [ "${noeud}" = "worker" -o "${noeud}" = "master" -o "${noeud}" = "loadBalancer" ]
do
	echo -n 'Indiquez si cette machine doit être "loadBalancer ou master" ou "worker", mettre en toutes lettres votre réponse: '
	read noeud
done
vrai="1"
if [ ${noeud} = "worker" ]
then
	x=0 ; until [ "${x}" -gt "0" -a "${x}" -lt "7" ] ; do echo -n "Mettez un numéro de ${noeud} à installer - 1 à 3 ... pour ${noeud}1-k8s.mon.dom, mettre: 1 : " ; read x ; done
	hostnamectl  set-hostname  ${noeud}${x}-k8s.mon.dom
	mkhosts
	systemctl restart NetworkManager
	export node="worker"
 	echo -n "Quelle version de Kubernetes voulez-vous installer? [mettre au minimum: v1.29] : "
  	read vk8s
   	export Version_k8s="$vk8s"
elif [ ${noeud} = "master" ]
then
	x=0 ; until [ "${x}" -gt "0" -a "${x}" -lt "4" ] ; do echo -n "Mettez un numéro de ${noeud} à installer - 1 à 3 ... pour ${noeud}1-k8s.mon.dom, mettre: 1 : " ; read x ; done
	hostnamectl  set-hostname  ${noeud}${x}-k8s.mon.dom
	mkhosts
	systemctl restart NetworkManager
	export node="master"
 	echo -n "Quelle version de Kubernetes voulez-vous installer? [mettre au minimum: v1.29] : "
  	read vk8s
   	export Version_k8s="$vk8s"
		if [ "${noeud}${x}-k8s.mon.dom" = "master1-k8s.mon.dom" ]
		then 
			first="yes"
			until [ "${Reseau}" == "calico" -o "${Reseau}" == "flannel" ]
   			do
      				echo -n "Quel type de réseau CNI voulez-vous déployer ? calico / flannel : "
      				read Reseau
	 		done
		else
			first="no"
		fi
elif [ ${noeud} = "loadBalancer" ]
then
	hostnamectl  set-hostname  loadBalancer-k8s.mon.dom
	export node="loadBalancer"
	mkhosts
fi && \
vrai="0"
nom="Etape ${numetape} - Construction du nom d hote à ${noeud}${x}-k8s.mon.dom"
verif
#
############################################################################################
#                                                                                          #
#                       Déploiement du LB  HAProxy                                         #
#                                                                                          #
############################################################################################
clear
if [ "${node}" = "loadBalancer" ]
then
	#################################################
	# 
	# Ouverture du passage des flux IN sur les interfaces réseaux du LB
	#
	vrai=1
	parefeuLB && \
	vrai="0"
	nom="Etape ${numetape} - Regles de firewall à trusted"
	verif
	################################################ 
	# installation des applications.
	#
	#
	vrai="1"
	dnf  install -y ${appHAProxy} && \
	vrai="0"
	nom="Etape ${numetape} - Installation des outils et services sur le LB HA Proxy. "
	verif
	#################################################
	# Configuration et montage volume lvm NFS sur /dev/vdb
	#
	#
	vrai="1"
	nfs && \
	vrai="0"
	nom="Etape ${numetape} - Configuration et montage volume lvm NFS sur /dev/vdb. "
	verif
	#################################################
	# 
	# Configuration et demarrage du LB HAProxy
	#
	#
	vrai="1"
	ConfHaProxy && \
 	setsebool -P haproxy_connect_any on && \
	systemctl enable --now haproxy && \
	vrai="0"
	nom="Etape ${numetape} - Configuration du LB HAProxy. "
	verif
	#################################################
	# 
	# Configuration du temps.
	#
	#
	vrai="1"
	temps && \
	vrai="0"
	nom="Etape ${numetape} - Synchronisation de l'horloge"
	verif
	#################################################
	# 
	# configuration du NAT sur LB HAproxy
	#
	vrai="1"
	firewall-cmd --permanent --add-masquerade && \
	firewall-cmd --reload && \
	vrai="0"
	nom="Etape ${numetape} - Mise en place du NAT"
	verif
fi

############################################################################################
#                                                                                          #
#                       Déploiement des masters Kubernetes                                 #
#                                                                                          #
############################################################################################

# installation des paramètres sur les noeuds master du cluster.
#
#
if [ "${node}" = "master" ]
then
	#################################################
	# 
	# Configuration des ports du gestionnaire firewalld sur le noeud
	#
	vrai=1
	parefeuNoeudsMaster && \
	vrai="0"
	nom="Etape ${numetape} - Configuration des ports du gestionnaire firewalld sur le noeud "
	verif
 	#
  	#################################################
   	#
	#  echange des clés ssh avec le LB
	vrai="1"
	CopyIdLB
	vrai="0"
	nom="Etape ${numetape} - echange des clés ssh avec le LB "
	verif
	if [ "${noeud}${x}-k8s.mon.dom" = "master2-k8s.mon.dom" -o "${noeud}${x}-k8s.mon.dom" = "master3-k8s.mon.dom" ]
	then 
		#################################################
		# 
		# Echange de clés ssh avec master1-k8s.mon.dom
		#
		vrai="1"
		CopyIdRootSrvSupp && \
		vrai="0"
		nom="Etape ${numetape} - Echange des clés ssh avec master1-k8s.mon.dom"
		verif
	fi
	# 
	#################################################
	# 
	# Suppression du swap
	#
	vrai="1"
	Swap && \
	vrai="0"
	nom="Etape ${numetape} - Configuration du Swap à off"
	verif
	#################################################
	# 
	# Installation du repo de Kubernetes
	#
	vrai="1"
	repok8s && \
	vrai="0"
	nom="Etape ${numetape} - Configuration du repo Kubernetes"
	verif
	#################################################
	# 
	# installation des applications.
	#
	vrai="1"
	dnf  install -y ${appmaster} && \
	vrai="0"
	nom="Etape ${numetape} - Installation des outils et services sur le master"
	verif
	#################################################
	# 
	# Configuration du temps.
	#
	vrai="1"
	temps && \
	vrai="0"
	nom="Etape ${numetape} - Synchronisation de l'horloge"
	verif
	#################################################
	# 
	# installation du modules bridge.
	#
	vrai="1"
	moduleBr && \
	vrai="0"
	nom="Etape ${numetape} - Installation du module de brige"
	verif
	#################################################
	# 
	# installation de containerd
	#
	vrai="1"
	containerd && \
	vrai="0"
	nom="Etape ${numetape} - Configuration et installation du service CONTAINERD , RUNC , CNI plugin"
	verif
	#################################################
	# 
	# Démarrage du service kubelet
	#
	vrai="1"
	StartServiceKubelet && \
	vrai="0"
	nom="Etape ${numetape} - Démarrage du service kubelet avec support IPTables"
	verif
	
	#################################################
	# 
	# deployement du master
	#
	vrai="1"
	if [ "$first" = "yes" ]
	then
		ssh root@loadBalancer-k8s.mon.dom 'sed -i -e "s|#    server noeud1|    server noeud1|g" /etc/haproxy/haproxy.cfg' && \
		ssh root@loadBalancer-k8s.mon.dom systemctl restart haproxy.service && \
  		if [ "$Reseau" == "calico" ]
		then
			echo "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
			echo "      Déploiement Kubernetes en cours avec Calico en CNI "
			echo "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
   			kubeadm config images pull
			kubeadm init --control-plane-endpoint 172.21.0.100:6443 --upload-certs  --pod-network-cidr 192.168.0.0/16 &> /root/noeudsupplementaires.txt && \
			#################################################
			vrai="0"
			nom="Etape ${numetape} - Cluster Kubernetes correctement initialisé"
			verif
			# 
			# permettre à root de temporairement gérer le cluster kubernetes
			#
			#
			vrai="1"
			export KUBECONFIG=/etc/kubernetes/admin.conf && \
			vrai="0"
			nom="Etape ${numetape} - Export de la variable KUBECONFIG"
			verif
			#################################################
			# 
			# Construire le réseau calico pour k8s
			#
			#
			vrai="1"
   			kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v${VersionCalico}/manifests/tigera-operator.yaml
			sleep 20
			kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v${VersionCalico}/manifests/tigera-operator.yaml
			kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v${VersionCalico}/manifests/custom-resources.yaml
			vrai="0"
			nom="Etape ${numetape} - Deploiement Calico v${VersionCalico} en CNI sur le cluster"
			verif
		elif [ "$Reseau" == "flannel" ]
		then
			echo "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
			echo "      Déploiement Kubernetes en cours avec Flannel en CNI "
			echo "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
			kubeadm init --control-plane-endpoint 172.21.0.100:6443 --upload-certs  --pod-network-cidr 10.244.0.0/16  &> /root/noeudsupplementaires.txt && \
			#################################################
			vrai="0"
			nom="Etape ${numetape} - Cluster Kubernetes correctement initialisé"
			verif
			# 
			# permettre à root de temporairement gérer le cluster kubernetes
			#
			#
			vrai="1"
			export KUBECONFIG=/etc/kubernetes/admin.conf && \
			vrai="0"
			nom="Etape ${numetape} - Export de la variable KUBECONFIG"
			verif
			#################################################
			# 
			# Construire le réseau flannel pour k8s
			#
			#
			vrai="1"
			kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml && \
			vrai="0"
			nom="Etape ${numetape} - Deploiement Flannel v${VersionFlannel}"
			verif
		fi
		# 
		# autorisation du compte stagiaire à gérer le cluster kubernetes
		#
		#
		vrai="1"
		if [ "stagiaire" == "`grep stagiaire /etc/passwd | cut -f 1 -d ":"`" ]
		then
			mkdir  -p   /home/stagiaire/.kube
		else
			useradd -m stagiaire
			mkdir  -p   /home/stagiaire/.kube
		fi && \
		cp  -i   /etc/kubernetes/admin.conf  /home/stagiaire/.kube/config && \
		chown  -R  stagiaire:stagiaire   /home/stagiaire/.kube && \
		vrai="0"
		nom="Etape ${numetape} - Construction du compte stagiaire avec le controle de K8S"
		verif
 		# Installation de bash-completion pour faciliter les saisies
		#
		#
			##################################################
		#
		# choix du noeud maitre 2 ou 3
		#
		#
	elif [ "$first" = "no" ]
	then
 		#################################################
		# 
		# Récupération du token sur master1-k8s.mon.dom
		#
		vrai=1
		RecupToken
		vrai="0"
		nom="Etape ${numetape} - Recuperation du token sur le master pour l'intégration au cluster"
		verif
		#################################################
		# 
		# Intégration d'un noeud master au cluster
		#
		vrai="1"
		if [ "${noeud}${x}-k8s.mon.dom" = "master2-k8s.mon.dom" ]
		then 
			ssh root@loadBalancer-k8s.mon.dom 'sed -i -e "s|#    server noeud2|    server noeud2|g" /etc/haproxy/haproxy.cfg'
			ssh root@loadBalancer-k8s.mon.dom systemctl restart haproxy.service
		elif [ "${noeud}${x}-k8s.mon.dom" = "master3-k8s.mon.dom" ]
		then 
			ssh root@loadBalancer-k8s.mon.dom 'sed -i -e "s|#    server noeud3|    server noeud3|g" /etc/haproxy/haproxy.cfg'
			ssh root@loadBalancer-k8s.mon.dom systemctl restart haproxy.service
		fi && 
		vrai="0"
		nom="Etape ${numetape} - Intégration du noeud ${noeud}${x}-k8s.mon.dom à la conf du LoadBalancer"
		verif
		echo "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
		echo "      Déploiement d'un nouveau master en cours "
		echo "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
		vrai="1"
		if [ `ssh root@master1-k8s.mon.dom ls mesimages.tar` ]
		then
			scp root@master1-k8s.mon.dom:mesimages.tar  ./
		else
   			echo "Construction de l'archive des Images sur master1-k8s.mon.dom"
			ssh root@master1-k8s.mon.dom 'ctr --namespace k8s.io images export mesimages.tar $(ctr --namespace k8s.io images list -q)'
			scp root@master1-k8s.mon.dom:mesimages.tar  ./
		fi && \
		vrai="0"
		nom="Etape ${numetape} - Copie de l'archive mesimages.tar à partir de master1-k8s.mon.dom"
		verif
		vrai="1"
  		echo "Import des Images"
		ctr --namespace k8s.io images import mesimages.tar && \
		vrai="0"
		nom="Etape ${numetape} - Intégration des images k8s dans ${noeud}${x}-k8s.mon.dom"
		verif
		vrai="1"
		kubeadm join 172.21.0.100:6443 --token ${token} --discovery-token-ca-cert-hash sha256:${tokensha} ${CertsKey}  && \
		vrai="0"
		nom="Etape ${numetape} - Intégration du noeud ${noeud}${x}-k8s.mon.dom au cluster K8S"
		verif
	fi

fi
############################################################################################
#                                                                                          #
#                       Déploiement des workers Kubernetes                                 #
#                                                                                          #
############################################################################################
if [ "${node}" = "worker" ]
then
	#################################################
	# 
	# Configuration des ports du gestionnaire firewalld sur le noeud
	#
	vrai=1
	parefeuNoeudsWorker && \
	vrai="0"
	nom="Etape ${numetape} - Configuration des ports du gestionnaire firewalld sur le noeud "
	verif
 	#################################################
	#
	# Echange des clés ssh avec master1-k8s.mon.dom
	#
	vrai="1"
	ssh-keygen -b 4096 -t rsa -f ~/.ssh/id_rsa -P "" && \
	CopyIdRoot && \
	vrai="0"
	nom="Etape ${numetape} - Echange des clés ssh avec master1-k8s.mon.dom"
	verif
	#################################################
	# 
	# Suppression du swap
	#
	vrai="1"
	Swap && \
	vrai="0"
	nom="Etape ${numetape} - Configuration du Swap à off"
	verif
	#################################################
	# 
	# Configuration SELinux à permissive.
	#
	#vrai="1"
	#SELinux && \
	#vrai="0"
	#nom="Etape ${numetape} - Configuration du SElinux à : disabled "
	#verif
	#################################################
	# 
	# Installation du repo de Kubernetes
	#
	vrai="1"
	repok8s && \
	vrai="0"
	nom="Etape ${numetape} - Installation du repo de Kubernetes"
	verif
	#################################################
	# 
	# Installation des outils
	#
	vrai="1"
	dnf install -y ${appworker} && \
	vrai="0"
	nom="Etape ${numetape} - Installation de outils sur le worker"
	verif
	#################################################
	#
	# synchronisation de temps
	#
	vrai="1"
	temps && \
	vrai="0"
	nom="Etape ${numetape} - Configuration de l'horloge"
	verif
	#################################################
	# 
	# Chargement du module noyau de bridge
	#
	vrai="1"
	moduleBr && \
	vrai="0"
	nom="Etape ${numetape} - Installation du module bridge sur le worker"
	verif
	#################################################
	# 
	# installation de containerd
	#
	vrai="1"
	containerd && \
	vrai="0"
	nom="Etape ${numetape} - Configuration et installation du service CONTAINERD , RUNC , CNI plugin"
	verif
	#################################################
	# 
	# Démarrage du service kubelet
	#
	vrai="1"
	StartServiceKubelet && \
	vrai="0"
	nom="Etape ${numetape} - Demarrage du service kubelet sur le worker"
	verif
	##############################################
	#
	# Recuperation du token sur le master pour l'intégration au cluster
	#
	vrai="1"
	RecupToken && \
	vrai="0"
	nom="Etape ${numetape} - Recuperation du token sur le master pour l'intégration au cluster"
	verif
	#################################################
	# 
	# Jonction de l'hôte au cluster
	#
	vrai="1"
	echo "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
	echo "      Déploiement d'un nouveau worker en cours "
	echo "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
	vrai="1"
	if [ `ssh root@master1-k8s.mon.dom ls mesimages.tar` ]
	then
 		scp root@master1-k8s.mon.dom:mesimages.tar  ./
	else
 		echo "Construction de l'archive des Images sur master1-k8s.mon.dom"
		ssh root@master1-k8s.mon.dom 'ctr --namespace k8s.io images export mesimages.tar $(ctr --namespace k8s.io images list -q)'
  		scp root@master1-k8s.mon.dom:mesimages.tar  ./
	fi && \
	vrai="0"
	nom="Etape ${numetape} - Copie de l'archive mesimages.tar à partir de master1-k8s.mon.dom"
	verif
	vrai="1"
 	echo "Import des Images"
	ctr --namespace k8s.io images import mesimages.tar && \
	vrai="0"
	nom="Etape ${numetape} - Intégration des images k8s dans ${noeud}${x}-k8s.mon.dom"
	verif
	vrai="1"
	kubeadm join "172.21.0.100:6443" --token ${token}  --discovery-token-ca-cert-hash sha256:${tokencaworker} && \
	vrai="0"
	nom="Etape ${numetape} - Intégration du noeud worker au cluster"
	verif
fi
