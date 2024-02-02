# liens d'accès aux VMs de bases.
# https://drive.google.com/file/d/1CzqLZtR1P1erMNBXyi7qyDV9xUfFwy1K/view?usp=drivesdk
#!/bin/sh
set -e
#   Version script		: 3.0
#   Deploiement sur Rocky Linux : 8
#   Version kubelet		: 1.29 +
#   Version Containerd		: 1.7.11
#   Version RunC 		: 1.1.11
#   Version CNI-Plugin		: 1.4.0
#   Version calico		: 3.27.O
#   Version minimal Kubelet	: 1.29
#
#   Script de déploiment kubernetes en multi-masters avec LB HAPROXY
#   By christophe.merle@gmail.com
#
# Script destiné à faciliter le déploiement de cluster kubernetes en multi-master
# Il est à exécuter dans le cadre d'une formation.
# Il ne doit pas être exploité en l'état pour un déploiement en production.
#
#
#
#################################################################################
#                                                                               #
#                       LABS  Kubernetes                                        #
#                                                                               #
#                                                                               #
#               Internet                                                        #
#                   |                                                           #
#                 (VM) LB Nginx DHCPD NAMED NAT SQUID cache                     #
#                              |                                                #
#                 (vm master1) |                                                #
#                        |     | (vm master2)                                   #
#                        |     |  |     (VM master3)                            #
#                        |     |  |     |                                       #
#                        |     |  |     |                                       #
#                      -------------------                                      #
#                      |  switch  interne|--(VM) Client linux                   #
#                      |-----------------|                                      #
#                        |     |      |                                         #
#                        |     |      |                                         #
#                 (vm)worker1  |      |                                         #
#                      (vm)worker2    |                                         #
#                            (vm) worker3                                       #
#                                                                               #
#                                                                               #
#                                                                               #
#################################################################################
#                                                                               #
#                          Features                                             #
#                                                                               #
#################################################################################
#                                                                               #
# - Le système sur lequel s'exécute ce script doit être un Rocky Linux 8        #
# - Le compte root doit etre utilisé pour exécuter ce Script                    #
# - Le script requière :		        				#
#	*  L'outil vitualbox (le cluster fonctionne dans un réseau privé)       #
#	*  Le loadBalancer à deux interfaces réseaux :			        #
#		- La première en bridge/dhcp				        #
#       	- La seconde dans le réseau privé est attendu à 172.21.0.100/24 #
#   	*  Les adresses/noms des noeuds sont automatiquement attribuées		#
# - Le réseau overlay est gérer par VxLAN à l'aide de Calico                    #
# - Les systèmes sont synchronisés sur le serveur de temps zone Europe/Paris    #
# - Les services NAMED et DHCPD sont installés sur le loadBalancer		#
# - Le LABS est établie avec un maximum de 3 noeuds masters & 6 noeuds workers  #
# - L'API est joignable par le loadBalancer sur l'adresse 172.21.0.100:6443     #
#                                                                               #
#################################################################################
#
#
###########################################################################################
#                                                                               	  #
#                      Déclaration des variables                                	  #
#                                                                               	  #
###########################################################################################
#
export numetape=0
export NBR=0
export appmaster="wget tar bind-utils nfs-utils kubelet iproute-tc kubelet kubeadm kubectl cri-tools kubernetes-cni --disableexcludes=kubernetes"
export appworker="wget tar bind-utils nfs-utils kubelet iproute-tc kubeadm kubectl cri-tools kubernetes-cni --disableexcludes=kubernetes"
export appHAProxy="wget haproxy bind bind-utils iproute-tc policycoreutils-python-utils dhcp-server"
export VersionContainerD="1.7.11"
export VersionRunC="1.1.11"
export VersionCNI="1.4.0"
export VersionCalico="3.27.0"
export Version_k8s="v1.29"
#                                                                               	  #
###########################################################################################
#                                                                               	  #
#                      Déclaration des fonctions                                	  #
#                                                                               	  #
###########################################################################################
#################################################
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
SELinux(){
	setenforce 0 && \
	sed -i 's/^SELINUX=enforcing$/SELINUX=disabled/' /etc/selinux/config
	grubby --update-kernel ALL --args selinux=0
}
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
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF
}
#################################################
# 

# Fonction d'installation de containerd en derniere version stable
#
containerd(){
if [ -f containerd-${VersionContainerD}-linux-amd64.tar.gz ]
then
	tar Cxzf /usr/local/ containerd-${VersionContainerD}-linux-amd64.tar.gz
else
	wget  https://github.com/containerd/containerd/releases/download/v${VersionContainerD}/containerd-${VersionContainerD}-linux-amd64.tar.gz && \
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
	wget https://github.com/opencontainers/runc/releases/download/v${VersionRunC}/runc.amd64 && \
	install -m  755 runc.amd64  /usr/local/bin/runc
fi
if [ -f cni-plugins-linux-amd64-v${VersionCNI}.tgz ]
then
mkdir -p /opt/cni/bin && \
tar Cxzf /opt/cni/bin/ cni-plugins-linux-amd64-v${VersionCNI}.tgz
else
wget https://github.com/containernetworking/plugins/releases/download/v${VersionCNI}/cni-plugins-linux-amd64-v${VersionCNI}.tgz && \
mkdir -p /opt/cni/bin && \
tar Cxzf /opt/cni/bin/ cni-plugins-linux-amd64-v${VersionCNI}.tgz
fi
}
#################################################
# 

# Fonction de configuration de /etc/named.conf & /etc/named/rndc.conf
#
named(){
chown root:dhcpd /var/named && \
chown root:dhcpd /etc/named && \
cat <<EOF | tee /var/named/rndc.conf
# Start of rndc.conf
key "rndc-key" {
	algorithm hmac-sha256;
	secret "NhuVu5l48qkjmAL32GRfIy/rzcGtSLeRyMxki+GRuyg=";
};
options {
	default-key "rndc-key";
	default-server 127.0.0.1;
	default-port 953;
};
# End of rndc.conf
# Use with the following in named.conf, adjusting the allow list as needed:
# key "rndc-key" {
#       algorithm hmac-sha256;
#       secret "NhuVu5l48qkjmAL32GRfIy/rzcGtSLeRyMxki+GRuyg=";
# };
#
# controls {
#       inet 127.0.0.1 port 953
#               allow { 127.0.0.1;172.21.0.100; } keys { "rndc-key"; };
# };
# End of named.conf
EOF
cat <<EOF | tee /etc/named.conf
options {
	listen-on port 53 { 172.21.0.100; 127.0.0.1; };
	listen-on-v6 port 53 { ::1; };
	directory       "/etc/named";
	dump-file       "/var/named/data/cache_dump.db";
	statistics-file "/var/named/data/named_stats.txt";
	memstatistics-file "/var/named/data/named_mem_stats.txt";
	secroots-file   "/var/named/data/named.secroots";
	recursing-file  "/var/named/data/named.recursing";
	allow-query     { any; };
	allow-new-zones yes;
	recursion yes;
	forwarders {8.8.8.8; 8.8.4.4; };
	dnssec-validation yes;
	managed-keys-directory "/var/named/dynamic";
	geoip-directory "/usr/share/GeoIP";
	pid-file "/run/named/named.pid";
	session-keyfile "/run/named/session.key";
	include "/etc/crypto-policies/back-ends/bind.config";
};
zone "." IN {
	type hint;
	file "/var/named/named.ca";
};
include "/etc/named.root.key";
zone "mon.dom" in {
	type master;
	inline-signing yes;
	auto-dnssec maintain;
	file "/var/named/mon.dom.db";
	allow-update { key "rndc-key"; };
	allow-query { any;};
	notify yes;
	max-journal-size 50k;
};
key "rndc-key" {
       algorithm hmac-sha256;
       secret "NhuVu5l48qkjmAL32GRfIy/rzcGtSLeRyMxki+GRuyg=";
};
controls {
	inet 127.0.0.1 port 953
		allow { 127.0.0.1;172.21.0.100; } keys { "rndc-key"; };
};
zone "0.21.172.in-addr.arpa" in {
	type master;
	inline-signing yes;
	auto-dnssec maintain;
	file "/var/named/0.21.172.in-addr.arpa.db";
	allow-update { key "rndc-key"; };
	allow-query { any;};
	notify yes;
	max-journal-size 50k;
};
EOF
}
#################################################
# 

# Fonction de configuration de la zone direct mon.dom
#
namedMonDom(){
cat <<EOF | tee /var/named/mon.dom.db
\$TTL 300
@       IN SOA  loadBalancer-k8s.mon.dom. root.loadBalancer-k8s.mon.dom. (
	      1       ; serial
	      600      ; refresh
	      900      ; retry
	      3600      ; expire
	      300 )    ; minimum
@             NS      loadBalancer-k8s.mon.dom.
loadBalancer-k8s   A       172.21.0.100
traefik     CNAME   worker1-k8s.mon.dom.
w1          CNAME   worker2-k8s.mon.dom.
w2          CNAME   worker3-k8s.mon.dom.
w3          CNAME   worker1-k8s.mon.dom.
w4          CNAME   worker2-k8s.mon.dom.
EOF
}
#################################################
# 

# Fonction de configuration de la zone reverse named
#
namedRevers(){
cat <<EOF | tee /var/named/0.21.172.in-addr.arpa.db
\$TTL 300
@       IN SOA  loadBalancer-k8s.mon.dom. root.loadBalancer-k8s.mon.dom. (
	      1       ; serial
	      600      ; refresh
	      900      ; retry
	      3600      ; expire
	      300 )    ; minimum
@             NS      loadBalancer-k8s.mon.dom.
100           PTR     loadBalancer-k8s.mon.dom.
EOF
chown -R named:dhcpd /etc/named/ && \
chmod 770 /etc/named && \
chown -R named:dhcpd /var/named/ && \
chmod 660 /var/named/mon.dom.db && \
chmod 660 /var/named/0.21.172.in-addr.arpa.db && \
chmod -R 770 /var/named/dynamic
}
#################################################
# 

# Fonction de configuration des parametres communs du dhcp
#
dhcp(){
cat <<EOF | tee /etc/dhcp/dhcpd.conf
ddns-updates on;
ddns-update-style interim;
ignore client-updates;
update-static-leases on;
log-facility local7;
key "rndc-key" {
	algorithm hmac-sha256;
	secret "NhuVu5l48qkjmAL32GRfIy/rzcGtSLeRyMxki+GRuyg=";
};
zone mon.dom. {
  primary 172.21.0.100;
  key rndc-key;
}
zone 0.21.172.in-addr.arpa. {
  primary 172.21.0.100;
  key rndc-key;
}
option domain-name "mon.dom";
option domain-name-servers 172.21.0.100;
default-lease-time 600;
max-lease-time 7200;
authoritative;
subnet 172.21.0.0 netmask 255.255.255.0 {
  range 172.21.0.101 172.21.0.109;
  option routers 172.21.0.100;
  option broadcast-address 172.21.0.255;
  ddns-domainname "mon.dom.";
  ddns-rev-domainname "in-addr.arpa.";
}
EOF
}
#################################################
# 

# Fonction  de configuration du swap à off
#
Swap(){
swapoff   -a && \
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
}
######################################################################
#

# Fonction de configuration du module bridge
#
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
#######################################################################
#

# Fonction de serveur de temps
#
temps(){
timedatectl set-timezone "Europe/Paris" && \
timedatectl set-ntp true
}
#######################################################################
#

# Fonction de création des clés pour ssh-copy-id
#
CopyIdRootSrvSupp(){
ssh-copy-id -i ~/.ssh/id_rsa.pub root@master1-k8s.mon.dom
}
#######################################################################
#

# Fonction de création des clés pour ssh-copy-id
#
CopyIdRoot(){
ssh-keygen -b 4096 -t rsa -f ~/.ssh/id_rsa -P "" && \
ssh-copy-id -i ~/.ssh/id_rsa.pub root@master1-k8s.mon.dom
}
#######################################################################
#

# Fonction de création des clés pour ssh-copy-id
#
CopyIdLB(){
ssh-keygen -b 4096 -t rsa -f ~/.ssh/id_rsa -P "" && \
ssh-copy-id -i ~/.ssh/id_rsa.pub root@loadBalancer-k8s.mon.dom
}
#######################################################################
#

# Fonction de récupération du token et sha256 de cacert
#
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
#################################################
# 

# Démarrage du service kubelet
#
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
#####################################################################
#

# configuration du service haproxy
#
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
parefeuLB(){
firewall-cmd  --set-default-zone trusted && \
firewall-cmd --add-interface=lo --zone=trusted --permanent && \
firewall-cmd --reload
}
#################################################
# 

# Ouverture du passage des flux IN sur les interfaces réseaux
#
parefeuNoeuds(){
systemctl disable --now firewalld
}
###################################################################################################
#                                                                                                 #
#                             Debut de la séquence d'Installation                                 #
#                                                                                                 #
###################################################################################################




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
	x=0 ; until [ "${x}" -gt "0" -a "${x}" -lt "7" ] ; do echo -n "Mettez un numéro de ${noeud} à installer - 1 à 6 ... pour ${noeud}1-k8s.mon.dom, mettre: 1 : " ; read x ; done
	hostnamectl  set-hostname  ${noeud}${x}-k8s.mon.dom
	systemctl restart NetworkManager
	export node="worker"
 	echo -n "Quelle version de Kubernetes voulez-vous installer? [mettre au minimum: v1.29] : "
  	read vk8s
   	export Version_k8s="$vk8s"
elif [ ${noeud} = "master" ]
then
	x=0 ; until [ "${x}" -gt "0" -a "${x}" -lt "4" ] ; do echo -n "Mettez un numéro de ${noeud} à installer - 1 à 3 ... pour ${noeud}1-k8s.mon.dom, mettre: 1 : " ; read x ; done
	hostnamectl  set-hostname  ${noeud}${x}-k8s.mon.dom
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
fi && \
vrai="0"
nom="Etape ${numetape} - Construction du nom d hote à ${noeud}${x}-k8s.mon.dom"
verif

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
	# 
	# Configuration et démarrage du serveur BIND9.
	#
	#
	vrai="1"
	echo 'OPTIONS="-4"' >> /etc/sysconfig/named && \
	named && \
	namedMonDom && \
	namedRevers && \
	semanage permissive -a named_t && \
	systemctl enable --now named.service && \
	vrai="0"
	nom="Etape ${numetape} - Configuration et demarrage de bind"
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
	#################################################
	# 
	# configuration du dhcp avec inscription dans le DNS
	#
	#
	vrai="1"
	dhcp && \
	sed -i 's/.pid/& 'enp0s8'/' /usr/lib/systemd/system/dhcpd.service && \
	vrai="0"
	nom="Etape ${numetape} - Installation et configuration du service DHCP sur loadBalancer-k8s.mon.dom"
	verif
	################################################
	#
	# modification des droits SELINUX sur dhcpd et start du service
	#
	#
	vrai="1"
	semanage permissive -a dhcpd_t && \
	systemctl enable  --now  dhcpd.service && \
	vrai="0"
	nom="Etape ${numetape} - restart du service dhcpd avec droits SELINUX"
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
	# Désactivation du gestionnaire firewalld sur le noeud
	#
	vrai=1
	parefeuNoeuds && \
	vrai="0"
	nom="Etape ${numetape} - Désactivation du gestionnaire firewalld sur le noeud "
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
	# Configuration SELinux à permissive.
	#
	vrai="1"
	SELinux && \
	vrai="0"
	nom="Etape ${numetape} - Configuration du SElinux à : disabled "
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
	# Désactivation du gestionnaire firewalld sur le noeud
	#
	vrai=1
	parefeuNoeuds && \
	vrai="0"
	nom="Etape ${numetape} - Désactivation du gestionnaire firewalld sur le noeud "
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
	vrai="1"
	SELinux && \
	vrai="0"
	nom="Etape ${numetape} - Configuration du SElinux à : disabled "
	verif
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
