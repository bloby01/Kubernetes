#!/bin/bash
#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
#   !!!									!!!
#   !!!		           ATTENTION					!!!
#   !!!									!!!
#   !!!		   Déployement NON FONCTIONNEL EN L'ETAT		!!!
#   !!!				+					!!!
#   !!!		   Vérifier le proxy avec login et password		!!!
#   !!!									!!!
# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
#   Version : 1.0
#   Deploiement sur Rocky Linux 8.4 minimum
#
#
# Script de déploiment kubernetes
# By christophe@cmconsulting.online
#
# Script destiné à faciliter le déploiement de cluster kubernetes
# Il est à exécuter dans le cadre d'une formation.
# Il ne doit pas être exploité pour un déploiement en production.
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
#                 (VM) LB Nginx DHCPD NAMED NAT                                 #
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
# - Le système sur lequel s'exécute ce script doit être un Rocky Linux 8.4      #
# - Le compte root doit etre utilisé pour exécuter ce Script                    #
# - Le script requière que la machine master soit correctement configuré sur IP #
#   master-k8s.mon.dom carte interne enp0s8 -> 172.21.0.100/24 (pré-configurée) #
#   master-k8s.mon.dom carte externe enp0s3 -> XXX.XXX.XXX.XXX/YY               #
# - Le réseau overlay est gérer par IPIP à l'aide de Calico                     #
# - Les systèmes sont synchronisés sur le serveur de temps zone Europe/Paris    #
# - Les noeuds Master & Minions sont automatiquements adressé sur IP par le LB  #
# - La résolution de nom est réaliser par un serveur BIND9 sur le LB            #
# - Le LABS est établie avec un maximum de 3 noeuds masters & 6 noeuds workers  #
# - Le compte d'exploitation du cluster est "stagiaire avec MDP: Azerty01"      #
#                                                                               #
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
numetape=0
NBR=0
appmaster="nfs-utils kubelet kubeadm kubectl  --disableexcludes=kubernetes"
appworker="nfs-utils kubelet kubeadm --disableexcludes=kubernetes"
#appworker="nfs-utils iproute-tc kubelet kubeadm --disableexcludes=kubernetes"
appHAProxy="haproxy bind bind-utils iproute-tc dhcp-server"
NoProxyAdd=".mon.dom,172.21.0.100,172.21.0.101,172.21.0.102,172.21.0.110,172.21.0.111,172.21.0.112,172.21.0.113,172.21.0.114,172.21.0.115,localhost,127.0.0.1"
#                                                                               	  #
###########################################################################################
#                                                                               	  #
#                      Déclaration des fonctions                                	  #
#                                                                               	  #
###########################################################################################

#Fonction de vérification des étapes
verif(){
numetape=`expr ${numetape} + 1 `
  if [ "${vrai}" -eq "0" ]; then
    echo "Machine: ${node}${x}-k8s.mon.dom - ${nom} - OK"
  else
    echo "Erreur sur Machine: ${node}${x}-k8s.mon.dom - ${nom} - ERREUR"
    exit 0
  fi
}

# Fonction d'installation de docker-CE en derniere version stable
docker(){
vrai="1"
curl -o /etc/yum.repos.d/docker-ce.repo https://download.docker.com/linux/centos/docker-ce.repo
dnf  install -y docker-ce && \
mkdir -p /etc/docker
cat <<EOF > /etc/docker/daemon.json
{
  "exec-opts": ["native.cgroupdriver=systemd"]
}
EOF
systemctl enable  --now docker.service && \
vrai="0"
nom="Déploiement de docker sur le noeud"
verif
}

# Fonction de configuration des parametres communs du dhcp
dhcp () {
vrai="1"
cat <<EOF > /etc/dhcp/dhcpd.conf
ddns-updates on;
ddns-update-style interim;
ignore client-updates;
update-static-leases on;
log-facility local7;
include "/etc/named/ddns.key";
zone mon.dom. {
  primary 172.21.0.100;
  key DDNS_UPDATE;
}
zone 0.21.172.in-addr.arpa. {
  primary 172.21.0.100;
  key DDNS_UPDATE;
}
option domain-name "mon.dom";
option domain-name-servers 172.21.0.100;
default-lease-time 600;
max-lease-time 7200;
authoritative;
subnet 172.21.0.0 netmask 255.255.255.0 {
  range 172.21.0.101 172.21.0.115;
  option routers 172.21.0.100;
  option broadcast-address 172.21.0.255;
  ddns-domainname "mon.dom.";
  ddns-rev-domainname "in-addr.arpa";
}
EOF
vrai="0"
nom="Installation et configuration de dhcp sur master"
}

# Fonction de configuration du serveur Named maitre SOA
named () {
vrai="1"
cat <<EOF >> /etc/named.conf
include "/etc/named/ddns.key" ;
zone "mon.dom" IN {
        type master;
        file "mon.dom.db";
        allow-update {key DDNS_UPDATE;};
        allow-query { any;};
        notify yes;
};
zone "0.21.172.in-addr.arpa" IN {
        type master;
        file "172.21.0.db";
        allow-update {key DDNS_UPDATE;};
        allow-query { any;};
        notify yes;
};
EOF
vrai="0"
nom="Déclaration des zones dans named.conf"
}

# Fonction de configuration de la zone direct mon.dom
namedMonDom () {
vrai="1"
cat <<EOF > /var/named/mon.dom.db
\$TTL 300
@       IN SOA  haproxy-k8s.mon.dom. root.haproxy-k8s.mon.dom. (
              1       ; serial
              600      ; refresh
              900      ; retry
              3600      ; expire
              300 )    ; minimum
@             NS      haproxy-k8s.mon.dom.
haproxy-k8s   A       172.21.0.100
traefik     CNAME   worker1-k8s.mon.dom.
w1          CNAME   worker2-k8s.mon.dom.
w2          CNAME   worker3-k8s.mon.dom.
EOF
vrai="0"
nom="Configuration du fichier de zone mondom.db"
}

# Fonction de configuration de la zone reverse named
namedRevers () {
vrai="1"
cat <<EOF > /var/named/172.21.0.db
\$TTL 300
@       IN SOA  haproxy-k8s.mon.dom. root.haproxy-k8s.mon.dom. (
              1       ; serial
              600      ; refresh
              900      ; retry
              3600      ; expire
              300 )    ; minimum
@             NS      haproxy-k8s.mon.dom.
100           PTR     haproxy-k8s.mon.dom.
EOF
vrai="0"
nom="Configuration du fichier de zone 0.21.172.in-addr.arpa.db"
}

# Fonction de configuration du repo k8s
repok8s () {
vrai="1"
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kube*
EOF
vrai="0"
nom="Configuration du repository yum pour kubernetes"
}

# Fonction  de configuration du SElinux et du swap à off
Swap () {
vrai="1"
swapoff   -a && \
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab && \
vrai="0"
nom="Désactivation du Swap"
}

# Fonction de configuration du module bridge
moduleBr () {
vrai="1"
modprobe  br_netfilter && \
cat <<EOF > /etc/rc.modules
modprobe  br_netfilter
EOF
chmod  +x  /etc/rc.modules && \
sysctl   -w net.bridge.bridge-nf-call-iptables=1 && \
sysctl   -w net.bridge.bridge-nf-call-ip6tables=1 && \
cat <<EOF > /etc/sysctl.conf
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
EOF
vrai="0"
nom="Configuration du module br_netfilter"
}

# Fonction de serveur de temps
temps() {
vrai="1"
timedatectl set-timezone "Europe/Paris" && \
#timedatectl set-timezone Europe/paris && \
timedatectl set-ntp true && \
vrai="0"
nom="Configuration du serveur de temps"
}

# Fonction  de configuration de profil avec proxy auth
profilproxyauth() {
vrai="1"
cat <<EOF >> /etc/profile
export HTTP_PROXY="http://${proxLogin}:${proxyPassword}@${proxyUrl}"
export HTTPS_PROXY="${HTTP_PROXY}"
export http_proxy="${HTTP_PROXY}"
export https_proxy="${HTTP_PROXY}"
export no_proxy="${NoProxyAdd}"
export NO_PROXY="${NoProxyAdd}"
EOF
vrai="0"
nom="Configuration du fichier /etc/profil avec proxy auth"
}

# Fonction de configuration de yum avec proxy auth
dnfproxyauth() {
vrai="1"
cat <<EOF >> /etc/dnf/dnf.conf
proxy=http://${proxyUrl}
proxy_username=${proxLogin}
proxy_password=${proxyPassword}
EOF
vrai="0"
nom="Configuration de yum avec proxy auth"
}

# Fonction de configuration de proxy pour docker avec auth
dockerproxyauth() {
vrai="1"
cat <<EOF >> /etc/systemd/system/docker.service.d/http-proxy.conf
[Service]
Environment="HTTP_PROXY=http://${proxLogin}:${proxyPassword}@${proxyUrl}" "NO_PROXY=${NoProxyAdd}"
EOF
cat <<EOF >> /etc/systemd/system/docker.service.d/https-proxy.conf
[Service]
Environment="HTTPS_PROXY=http://${proxLogin}:${proxyPassword}@${proxyUrl}" "NO_PROXY=${NoProxyAdd}"
EOF
systemctl daemon-reload
vrai="0"
nom="Configuration de docker avec proxy auth"
}

# Fonction de configuration du client docker avec proxy auth
clientdockerproxyauth() {
vrai="1"
cat <<EOF >> /home/stagiaire/.docker/config.json
{
  "proxies":
  {
    "default":
    {
      "httpProxy": "http://${proxLogin}:${proxyPassword}@${proxyUrl}"
      "httpsProxy": "http://${proxLogin}:${proxyPassword}@${proxyUrl}"
      "noProxy": "${NoProxyAdd}"
    }
  }
}
EOF
vrai="0"
nom="Configuration du client docker avec proxy auth"
}

# Fonction  de configuration de profil avec proxy
profilproxy() {
vrai="1"
cat <<EOF >> /etc/profile
export HTTP_PROXY="http://${proxyUrl}"
export HTTPS_PROXY="${HTTP_PROXY}"
export http_proxy="${HTTP_PROXY}"
export https_proxy="${HTTP_PROXY}"
export no_proxy="${NoProxyAdd}"
export NO_PROXY="${NoProxyAdd}"
EOF
vrai="0"
nom="Configuration du fichier /etc/profil avec proxy"
}

# Fonction de configuration de yum avec proxy auth
dnfproxy() {
vrai="1"
cat <<EOF >> /etc/dnf/dnf.conf
proxy=http://${proxyUrl}
EOF
vrai="0"
nom="Configuration de yum avec proxy"
}

# Fonction de configuration de proxy pour docker
dockerproxy() {
vrai="1"
cat <<EOF >> /etc/systemd/system/docker.service.d/http-proxy.conf
[Service]
Environment="HTTP_PROXY=http://${proxyUrl}" "NO_PROXY=${NoProxyAdd}"
EOF
cat <<EOF >> /etc/systemd/system/docker.service.d/https-proxy.conf
[Service]
Environment="HTTPS_PROXY=http://${proxyUrl}" "NO_PROXY=${NoProxyAdd}"
EOF
systemctl daemon-reload
vrai="0"
nom="Configuration de docker avec proxy"
}

# Fonction de configuration de client docker avec proxy avec auth
clientdockerproxy() {
vrai="1"
cat <<EOF >> /home/stagiaire/.docker/config.json
{
  "proxies":
  {
    "default":
    {
      "httpProxy": "http://${proxyUrl}"
      "httpsProxy": "http://${proxyUrl}"
      "noProxy": "${NoProxyAdd}"
    }
  }
}
EOF
vrai="0"
nom="Configuration du client docker avec proxy"
}
# Fonction de création des clés pour ssh-copy-id
#
CopyIdRoot () {
#
ssh-keygen -b 4096 -t rsa -f ~/.ssh/id_rsa -P ""
ssh-copy-id -i ~/.ssh/id_rsa.pub root@172.21.0.100
}
# Fonction de récupération du token et sha253 de cacert
#
RecupToken () {
alias master1="ssh root@master1-k8s.mon.dom"
export token=`master1 kubeadm token list | tail -1 | cut -f 1,2 -d " "`
tokensha=`master1 openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //'`
export tokenca=sha256:${tokensha}
CertsKey=`kubeadm certs certificate-key` 
}

###################################################################################################
#                                                                                                 #
#                             Debut de la séquence d'Installation                                 #
#                                                                                                 #
###################################################################################################




############################################################################################
#                                                                                          #
#                       Paramètres communs HA Proxy, master et worker                      #
#                                                                                          #
############################################################################################
clear
until [ "${noeud}" = "worker" -o "${noeud}" = "master" -o "${noeud}" = "ha" ]
do
echo -n 'Indiquez si cette machine doit être "ha ou master" ou "worker", mettre en toutes lettres votre réponse: '
read noeud
done
if [ "${noeud}" = "worker" ]
then
vrai="1"
x=0 ; until [ "${x}" -gt "0" -a "${x}" -lt "7" ] ; do echo -n "Mettez un numéro de ${noeud} à installer (1, 2, 3, ... pour ${noeud}1-k8s.mon.dom, mettre: 1 ): " ; read x ; done
hostnamectl  set-hostname  ${noeud}${x}-k8s.mon.dom
export node="worker"
elif [ ${noeud} = "master" ]
then
vrai="1"
x=0 ; until [ "${x}" -gt "0" -a "${x}" -lt "4" ] ; do echo -n "Mettez un numéro de ${noeud} à installer (1, 2, 3, ... pour ${noeud}1-k8s.mon.dom, mettre: 1 ): " ; read x ; done
hostnamectl  set-hostname  ${noeud}${x}-k8s.mon.dom
export node="master"
	if [ "${noeud}${x}-k8s.mon.dom" = "master1-k8s.mon.dom" ]
	then 
	first="yes"
	else
	first="no"
	fi
elif [ ${noeud} = "ha" ]
then
vrai="1"
hostnamectl  set-hostname  haproxy-k8s.mon.dom
export node="haproxy"
vrai="0"
nom="Etape ${numetape} - Construction du nom d hote"
verif
fi
vrai="1"
x=0 ; until [ "${x}" = "y" -o "${x}" = "Y" -o "${x}" = "n" -o "${x}" = "N" ] ; do echo -n "Y a t il un serveur proxy pour sortir du réseau ? Y/N : " ; read x ; done
if [ "$x" = "y" -o "$x" = "Y" ]
then
prox="yes"
echo -n "Mettre l'url d'acces au format suivant <IP:PORT/>  : "
read proxyUrl
auth=0 ; until [ "${auth}" = "y" -o "${auth}" = "Y" -o "${auth}" = "n" -o "${auth}" = "N" ] ; do echo -n "Y a t il un login et un mot de passe pour passer le proxy ? Y/N : " ; read auth ; done
  if [ "$auth" = "y" -o "$auth" = "Y" ]
  then
  echo -n "Mettre votre login <jean> :  "
  read proxyLogin
  echo -n "Mettre votre mot de passe <password> :  "
  read proxyPassword
  clear
  fi
fi

vrai="0"
nom="Etape ${numetape} - Serveur proxy"
verif

#################################################
# 
# Ouverture du passage des flux IN sur les interfaces réseaux
#
#
vrai="1"
firewall-cmd  --set-default-zone trusted && \
firewall-cmd --add-interface=lo --zone=trusted --permanent && \
firewall-cmd --reload && \
vrai="0"
nom="Etape ${numetape} - Regles de firewall à trusted"
verif
#################################################
#
# Construction du fichier de résolution interne hosts.
# et déclaration du résolveur DNS client
#
#
vrai="1"
f="/etc/hosts"
cat <<EOF > ${f}
127.0.0.1 localhost
EOF
if [ -f "${f}" ]
then
vrai="0"
fi
nom="Etape ${numetape} - Contruction du fichier hosts"
verif
############################################################################################
#                                                                                          #
#                       Déploiement du LB  HA Proxy                                        #
#                                                                                          #
############################################################################################
if [ ${node} = "haproxy" ]
then
  if [ "$prox" = "yes" ]
  then
    if [ "$auth" = "y" -o "$auth" = "Y" ]
    then
    profilproxyauth
    dnfproxyauth
    ###############  fin de la conf proxy avec auth
    elif [ "$auth" = "n" -o "$auth" = "N" ]
    then
    profilproxy
    dnfproxy
    fi
  fi
vrai="1"
clear
#################################################
# 
# Présentation des interfaces réseaux disponibles
#
#
echo ""
echo "liste des interfaces réseaux disponibles:"
echo ""
echo "-----------------------------------------"
echo "`ip link`"
echo ""
echo "-----------------------------------------"
echo ""
echo -n "Mettre le nom de l'interface réseaux Interne: "
read eth1 && \
Swap && \
vrai="0"
nom="Etape ${numetape} - Choix de l'interface interne. "
verif
#################################################
# 
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
# Configuration du LB HA Proxy
#
#
vrai="1"
cat <<EOF >> /etc/haproxy/haproxy.cfg
frontend kubernetes-frontend
    bind haproxy-k8s.mon.dom:6443
    mode tcp
    option tcplog
    default_backend kubernetes-backend

backend kubernetes-backend
    mode tcp
    option tcp-check
    balance roundrobin
    server master1-k8s.mon.dom master1-k8s.mon.dom:6443 check fall 3 rise 2
    server master2-k8s.mon.dom master2-k8s.mon.dom:6443 check fall 3 rise 2
    server master2-k8s.mon.dom master3-k8s.mon.dom:6443 check fall 3 rise 2
EOF
setsebool -P haproxy_connect_any on && \
systemctl enable --now haproxy && \
vrai="0"
nom="Etape ${numetape} - Configuration du LB HA Proxy. "
verif



#################################################
# 
# Configuration et démarrage du serveur BIND9.
#
#
vrai="1"
dnssec-keygen -a HMAC-MD5 -b 128 -r /dev/urandom -n USER DDNS_UPDATE && \
cat <<EOF > /etc/named/ddns.key
key DDNS_UPDATE {
	algorithm HMAC-MD5.SIG-ALG.REG.INT;
  secret "bad" ;
};
EOF
secret=`grep Key: ./*.private | cut -f 2 -d " "` && \
sed -i -e "s|bad|$secret|g" /etc/named/ddns.key && \
chown named:dhcpd /etc/named/ddns.key && \
chmod 640 /etc/named/ddns.key && \
sed -i -e "s|listen-on port 53 { 127.0.0.1; };|listen-on port 53 { 172.21.0.100; 127.0.0.1; };|g" /etc/named.conf && \
sed -i -e "s|allow-query     { localhost; };|allow-query     { localhost;172.21.0.0/24; };|g" /etc/named.conf && \
echo 'OPTIONS="-4"' >> /etc/sysconfig/named && \
named && \
namedMonDom && \
chown root:named /var/named/mon.dom.db && \
chmod 660 /var/named/mon.dom.db && \
namedRevers && \
chown root:named /var/named/172.21.0.db && \
chmod 660 /var/named/172.21.0.db && \
systemctl enable --now named.service && \
vrai="0"
nom="Etape ${numetape} - Configuration et demarrage de bind"
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
# configuration du NAT sur LB HA proxy
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
sed -i 's/.pid/& '"${eth1}"'/' /usr/lib/systemd/system/dhcpd.service && \
vrai="0"
nom="Etape ${numetape} - Configuration du service dhcp"
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
# 
# installation du repo kubernetes et des paramètres.
#
#
if [ "${node}" = "master" ]
then
  if [ "$prox" = "yes" ]
  then
    if [ "$auth" = "y" -o "$auth" = "Y" ]
    then
    profilproxyauth
    dnfproxyauth
      if [ -d /etc/systemd/system/docker.service.d/ ]
      then
      dockerproxyauth
      else
      mkdir -p /etc/systemd/system/docker.service.d/
      dockerproxyauth
      fi
      if [ -d /home/stagiaire/.docker/ ]
      then
      clientdockerproxyauth
      else
      mkdir -p /home/stagiaire/.docker/
      clientdockerproxyauth
      fi
      if [ -d /root/.docker/ ]
      then
      clientdockerproxyauth
      else
      mkdir -p /root/.docker/
      clientdockerproxyauth
      fi
    ################  fin de la conf proxy avec auth
    elif [ "$auth" = "n" -o "$auth" = "N" ]
    then
    profilproxy
    dnfproxy
      if [ -d /etc/systemd/system/docker.service.d/ ]
      then
      dockerproxy
      else
      mkdir -p /etc/systemd/system/docker.service.d/
      dockerproxy
      fi
      if [ -d /home/stagiaire/.docker ]
      then
      clientdockerproxy
      else
      mkdir -p /home/stagiaire/.docker
      clientdockerproxy
      fi
      if [ -d /root/.docker/ ]
      then
      clientdockerproxy
      else
      mkdir -p /root/.docker/
      clientdockerproxy
      fi
    fi
  fi
#################################################
# 
# installation des applications.
#
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
#
vrai="1"
temps && \
vrai="0"
nom="Etape ${numetape} - Synchronisation de l'horloge"
verif
#################################################
# 
# installation du modules bridge.
# et activation du routage
#
vrai="1"
moduleBr && \
vrai="0"
nom="Etape ${numetape} - Installation du module de brige"
verif
#################################################
# 
# Démarrage du service kubelet
#
#
vrai="1"
systemctl enable --now kubelet && \
vrai="0"
nom="Etape ${numetape} - Démarrage du service kubelet"
verif
#################################################
# 
# installation de docker
#
#
vrai="1"
docker && \
vrai="0"
nom="Etape ${numetape} - Configuration et installation du service docker-ee-stable"
#################################################
# 
# deployement du master
#
#
vrai="1"
if [ "$first" = "yes" ]
then
clear
echo "Est ce que le noeuds est bien : master1-k8s.mon.dom : ${node}${x}-k8s.mon.dom"
read tt
kubeadm init --control-plane-endpoint="haproxy-k8s.mon.dom:6443" --apiserver-advertise-address="${node}${x}-k8s.mon.dom" --apiserver-cert-extra-sans="*.mon.dom" --pod-network-cidr="192.168.0.0/16"  && \
#################################################
# 
# autorisation du compte stagiaire à gérer le cluster kubernetes
#
#
vrai="1"
useradd -m stagiaire
mkdir  -p   /home/stagiaire/.kube && \
cp  -i   /etc/kubernetes/admin.conf  /home/stagiaire/.kube/config && \
chown  -R  stagiaire:stagiaire   /home/stagiaire/.kube && \
vrai="0"
nom="Etape ${numetape} - Construction du compte stagiaire avec le controle de K8S"
verif
#################################################
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
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml && \
vrai="0"
nom="Etape ${numetape} - Deploiement calico"
verif
#################################################
# 
# Installation de bash-completion pour faciliter les saisies
#
#
vrai="1"
cat <<EOF >> /home/stagiaire/.bashrc
source <(kubectl completion bash)
EOF
vrai="0"
nom="Etape ${numetape} - Installation et configuration de stagiaire avec bash-completion"
verif
################################################
#
# Intégration du compte stagiaire au groupe docker
#
#
vrai="1"
usermod  -aG docker stagiaire && \
vrai="0"
nom="Etape ${numetape} - Intégration du compte stagiaire au groupe docker"
verif
elif [ "$first" = "no" ]
then
#################################################
# 
# Echange de clés ssh avec master1.k8s.mon.dom
#
vrai="1"
CopyIdRoot
vrai="0"
nom="Etape ${numetape} - Echange des clés ssh avec master1-k8s.mon.dom"
verif
#################################################
# 
# Récupération du token sur master1.k8s.mon.dom
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
echo "Est ce que le noeuds est bien : master2-k8s.mon.dom  ou master3-k8s.mon.dom : ${node}${x}-k8s.mon.dom"
read tt
kubeadm join haproxy-k8s.mon.dom:6443 --control-plane --token ${token} --apiserver-advertise-address="${node}${x}-k8s.mon.dom"  --discovery-token-ca-cert-hash ${tokenca} --certificate-key ${CertsKey} && \
vrai="0"
nom="Etape ${numetape} - Intégration du noeud  au cluster K8S"
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
  if [ "$prox" = "yes" ]
  then
    if [ "$auth" = "y" -o "$auth" = "Y" ]
    then
    profilproxyauth
    dnfproxyauth
      if [ -d /etc/systemd/system/docker.service.d/ ]
      then
      dockerproxyauth
      else
      mkdir -p /etc/systemd/system/docker.service.d/
      dockerproxyauth
      fi
      if [ -d /home/stagiaire/.docker/ ]
      then
      clientdockerproxyauth
      else
      mkdir -p /home/stagiaire/.docker/
      clientdockerproxyauth
      fi
      if [ -d /root/.docker/ ]
      then
      clientdockerproxyauth
      else
      mkdir -p /root/.docker/
      clientdockerproxyauth
      fi
    ################  fin de la conf proxy avec auth
    elif [ "$auth" = "n" -o "$auth" = "N" ]
    then
    profilproxy
    dnfproxy
      if [ -d /etc/systemd/system/docker.service.d/ ]
      then
      dockerproxy
      else
      mkdir -p /etc/systemd/system/docker.service.d/
      dockerproxy
      fi
      if [ -d /home/stagiaire/.docker/ ]
      then
      clientdockerproxy
      else
      mkdir -p /home/stagiaire/.docker/
      clientdockerproxy
      fi
      if [ -d /root/.docker/ ]
      then
      clientdockerproxy
      else
      mkdir -p /root/.docker/
      clientdockerproxy
      fi
    fi
  fi
#################################################
# 
# Constuction du fichier de configuration du repository de kubernetes
#
#
vrai="1"
repok8s && \
vrai="0"
nom="Etape ${numetape} - Construction du repository de K8S"
verif
#################################################
# 
# Suppression du swap
#
#
vrai="1"
Swap && \
vrai="0"
nom="Etape ${numetape} - Configuration du Swap à off"
verif
#################################################
# 
# Installation des outils
#
#
vrai="1"
yum install -y ${appworker} && \
vrai="0"
nom="Etape ${numetape} - Installation de outils sur le worker"
verif
#################################################
#
# synchronisation de temps
#
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
#
vrai="1"
moduleBr && \
vrai="0"
nom="Etape ${numetape} - Installation du module bridge sur le worker"
verif
#################################################
# 
# Démarrage du service kubelet
#
#
vrai="1"
systemctl enable --now kubelet && \
vrai="0"
nom="Etape ${numetape} - Demarrage du service kubelet sur le worker"
verif
#################################################
#
# Installation du moteur de conteneurisation docker
#
#
vrai="1"
docker && \
vrai="0"
nom="Etape ${numetape} - Installation du service docker-ce-stable sur le worker"
verif
#################################################
#
# Echange des clés ssh avec master1-k8s.mon.dom
#
vrai="1"
CopyIdRoot
vrai="0"
nom="Etape ${numetape} - Echange des clés ssh avec master1-k8s.mon.dom"
verif
#################################################
#
# Recuperation du token sur le master pour l'intégration au cluster
#
vrai="1"
RecupToken
vrai="0"
nom="Etape ${numetape} - Recuperation du token sur le master pour l'intégration au cluster"
verif

#################################################
# 
# Jonction de l'hôte au cluster
#
#
vrai="1"
kubeadm join "172.21.0.100:6443" --token ${token}  --discovery-token-ca-cert-hash ${tokenca} && \
vrai="0"
nom="Etape ${numetape} - Intégration du noeud worker au cluster"
verif
fi
