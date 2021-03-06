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
#   Deploiement sur CentOS 8 minimum.
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
# - Le système sur lequel s'exécute ce script doit être un CentOS8              #
# - Le compte root doit etre utilisé pour exécuter ce Script                    #
# - Le script requière que la machine master soit correctement configuré sur IP #
#   master-k8s.mon.dom carte interne enp0s8 -> 10.0.0.100/24 (pré-configurée) #
#   master-k8s.mon.dom carte externe enp0s3 -> XXX.XXX.XXX.XXX/YY               #
# - Le réseau sous-jacent du cluster est basé Calico                            #
# - Les systèmes sont synchronisés sur le serveur de temps zone Europe/Paris    #
# - Les noeuds Master & Minions sont automatiquements adressé sur IP par le LB  #
# - La résolution de nom est réaliser par un serveur BIND9 sur le LB            #
# - Le LABS est établie avec un maximum de 3 noeuds masters & 3 trois workers   #
# - Le compte d'exploitation du cluster est "stagiaire avec MDP: Azerty01"      #
#                                                                               #
#                                                                               #
#################################################################################
#                                                                               #
#                      Déclaration des variables                                #
#                                                                               #
#################################################################################
#

numetape=0
NBR=0
applb="nfs-utils bind bind-utils iproute-tc yum-utils dhcp-server kubectl --disableexcludes=kubernetes"
appmaster="nfs-utils bind-utils yum-utils iproute-tc kubelet kubeadm --disableexcludes=kubernetes"
appworker="nfs-utils bind-utils yum-utils iproute-tc kubelet kubeadm --disableexcludes=kubernetes"
export HOST0=master1-k8s.mon.dom
export HOST1=master2-k8s.mon.dom
export HOST2=master3-k8s.mon.dom

#                                                                               #
#################################################################################
#                                                                               #
#                      Déclaration des fonctions                                #
#                                                                               #
#################################################################################

# Fonction de récupération des outils pour le cours helm
githelm() {
git clone  https://github.com/bloby01/helm
cp -r helm /home/stagiaire
chown -R stagiaire:stagiaire helm
kubectl  create -f helm/nfs-client/deploy/
echo "---------------------------------------------------------------"
echo "le volumeClaim à utiliser sur NFS porte le nom: mon-volume-pvc"
echo "---------------------------------------------------------------"
}

# Fonction de configuration du serveur nfs
nfsconfigserver(){
mkdir -p /srv/nfs/kubedata
chown nobody: /srv/nfs/kubedata
cat <<EOF > /etc/exports
/srv/nfs/kubedata *(rw,sync,no_subtree_check,no_root_squash,no_all_squash,insecure)
EOF
systemctl enable --now nfs-server
}
#Fonction de vérification des étapes
verif(){
numetape=`expr ${numetape} + 1 `
echo " "
echo " "
if [ "${vrai}" -eq "0" ]; then
    echo "Machine: ${HOST} - ${nom} - OK"
  else
    echo "Erreur sur Machine: ${HOST} - ${nom} - ERREUR"
    exit 0
  fi
echo " "
echo "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
echo " "
}

# Fonction d'installation de docker-CE en derniere version
docker(){
yum install -y yum-utils
yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
yum-config-manager --enable docker-ce-stable
#yum -y install https://download.docker.com/linux/centos/7/x86_64/stable/Packages/containerd.io-1.2.6-3.3.el7.x86_64.rpm
yum  install  -y containerd.io
yum  install  -y docker-ce
systemctl enable  --now docker.service
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
  primary 10.0.0.100;
  key DDNS_UPDATE;
}
zone 0.0.10.in-addr.arpa. {
  primary 10.0.0.100;
  key DDNS_UPDATE;
}
option domain-name "mon.dom";
option domain-name-servers 10.0.0.100;
default-lease-time 600;
max-lease-time 7200;
authoritative;
subnet 10.0.0.0 netmask 255.255.255.0 {
  range 10.0.0.110 10.0.0.150;
  option routers 10.0.0.100;
  option broadcast-address 10.0.0.255;
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
zone "0.0.10.in-addr.arpa" IN {
        type master;
        file "10.0.0.db";
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
@       IN SOA  loadbalancer-k8s.mon.dom. root.loadbalancer-k8s.mon.dom. (
              1       ; serial
              600      ; refresh
              900      ; retry
              3600      ; expire
              300 )    ; minimum
@             NS      loadbalancer-k8s.mon.dom.
loadbalancer-k8s   A       10.0.0.100
traefik     CNAME   master1-k8s.mon.dom.
w1          CNAME   worker1-k8s.mon.dom.
EOF
vrai="0"
nom="Configuration du fichier de zone mondom.db"
}

# Fonction de configuration de la zone reverse named
namedRevers () {
vrai="1"
cat <<EOF > /var/named/10.0.0.db
\$TTL 300
@       IN SOA  loadbalancer-k8s.mon.dom. root.loadbalancer-k8s.mon.dom. (
              1       ; serial
              600      ; refresh
              900      ; retry
              3600      ; expire
              300 )    ; minimum
@             NS      loadbalancer-k8s.mon.dom.
100           PTR     loadbalancer-k8s.mon.dom.
EOF
vrai="0"
nom="Configuration du fichier de zone 0.0.10.in-addr.arpa.db"
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
selinuxSwap () {
vrai="1"
setenforce 0 && \
sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config && \
swapoff   -a && \
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab && \
vrai="0"
nom="Désactivation du selinux et du Swap"
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

# Fonction  de configuration de profil avec proxy auth
profilproxyauth() {
vrai="1"
cat <<EOF >> /etc/profile
export HTTP_PROXY="http://${proxLogin}:${proxyPassword}@${proxyUrl}"
export HTTPS_PROXY="${HTTP_PROXY}"
export http_proxy="${HTTP_PROXY}"
export https_proxy="${HTTP_PROXY}"
export no_proxy=".mon.dom,192.168.56.1,10.0.2.15,10.0.0.100,10.0.0.110,10.0.0.111,10.0.0.112,10.0.0.113,10.0.0.114,10.0.0.115,localhost,127.0.0.1"
export NO_PROXY="${no_proxy}"
EOF
vrai="0"
nom="Configuration du fichier /etc/profil avec proxy auth"
}

# Fonction de configuration de yum avec proxy auth
yumproxyauth() {
vrai="1"
cat <<EOF >> /etc/yum.conf
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
Environment="HTTP_PROXY=http://${proxLogin}:${proxyPassword}@${proxyUrl}" "NO_PROXY=.mon.dom,192.168.56.1,10.0.2.15,10.0.0.100,10.0.0.110,10.0.0.111,10.0.0.112,10.0.0.113,10.0.0.114,10.0.0.115,localhost,127.0.0.1"
EOF
cat <<EOF >> /etc/systemd/system/docker.service.d/https-proxy.conf
[Service]
Environment="HTTPS_PROXY=http://${proxLogin}:${proxyPassword}@${proxyUrl}" "NO_PROXY=.mon.dom,192.168.56.1,10.0.2.15,10.0.0.100,10.0.0.110,10.0.0.111,10.0.0.112,10.0.0.113,10.0.0.114,10.0.0.115,localhost,127.0.0.1"
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
      "noProxy": ".mon.dom,192.168.56.1,10.0.2.15,10.0.0.100,10.0.0.110,10.0.0.111,10.0.0.112,10.0.0.113,10.0.0.114,10.0.0.115,localhost,127.0.0.1"
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
export no_proxy=".mon.dom,192.168.56.1,10.0.2.15,10.0.0.100,10.0.0.110,10.0.0.111,10.0.0.112,10.0.0.113,10.0.0.114,10.0.0.115,localhost,127.0.0.1"
export NO_PROXY="${no_proxy}"
EOF
vrai="0"
nom="Configuration du fichier /etc/profil avec proxy"
}

# Fonction de configuration de yum avec proxy auth
yumproxy() {
vrai="1"
cat <<EOF >> /etc/yum.conf
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
Environment="HTTP_PROXY=http://${proxyUrl}" "NO_PROXY=.mon.dom,192.168.56.1,10.0.2.15,10.0.0.100,10.0.0.110,10.0.0.111,10.0.0.112,10.0.0.113,10.0.0.114,10.0.0.115,localhost,127.0.0.1"
EOF
cat <<EOF >> /etc/systemd/system/docker.service.d/https-proxy.conf
[Service]
Environment="HTTPS_PROXY=http://${proxyUrl}" "NO_PROXY=.mon.dom,192.168.56.1,10.0.2.15,10.0.0.100,10.0.0.110,10.0.0.111,10.0.0.112,10.0.0.113,10.0.0.114,10.0.0.115,localhost,127.0.0.1"
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
      "noProxy": ".mon.dom,192.168.56.1,10.0.2.15,10.0.0.100,10.0.0.110,10.0.0.111,10.0.0.112,10.0.0.113,10.0.0.114,10.0.0.115,localhost,127.0.0.1"
    }
  }
}
EOF
vrai="0"
nom="Configuration du client docker avec proxy"
}
###################################################################################################
#                                                                                                 #
#                             Debut de la séquence d'Installation                                 #
#                                                                                                 #
###################################################################################################




############################################################################################
#                                                                                          #
#                       Paramètres communs LoadBalancer, Masters, Minions                  #
#                                                                                          #
############################################################################################
clear
rm -f /etc/localtime
ln -s /usr/share/zoneinfo/Europe/Paris /etc/localtime

until [ "${noeud}" = "worker" -o "${noeud}" = "master" -o "${noeud}" = "loadbalancer" ]
do
echo -n 'Indiquez si cette machine doit être "loadbalancer", "master", "worker", mettre en toutes lettres votre réponse: '
read noeud
done

#######################
# Passage de proxy
#
#
vrai="1"
t=0 ; until [ "${t}" = "y" -o "${t}" = "Y" -o "${t}" = "n" -o "${t}" = "N" ] ; do echo -n "Y a t il un serveur proxy pour sortir du réseau ? Y/N : " ; read t ; done
if [ "${t}" = "y" -o "${t}" = "Y" ]
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
nom="Etape ${numetape} - Passage de proxy"
verif

#################################################
#
# Libre passage des flux in et out sur les interfaces réseaux
#
#
vrai="1"
firewall-cmd  --set-default-zone trusted && \
firewall-cmd --add-interface=lo --zone=trusted && \
firewall-cmd --add-interface=lo --zone=trusted --permanent && \
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
cat <<EOF > /etc/hosts
127.0.0.1 localhost
EOF
vrai="0"
nom="Etape ${numetape} - Contruction du fichier hosts"
verif

############################################################################################
#                                                                                          #
#                       Déploiement du LB nginx                                            #
#                                                                                          #
############################################################################################
#
vrai="1"
if [ "${noeud}" = "loadbalancer" ]
then
vrai="1"
hostnamectl  set-hostname  ${noeud}${x}-k8s.mon.dom && \
export HOST="${noeud}${x}-k8s.mon.dom" && \
export node="${noeud}" && \
cat <<EOF > /etc/resolv.conf
options ndots:15 timeout:1 attempts:5
domain mon.dom
nameserver 10.0.0.100
nameserver 8.8.8.8
EOF
vrai="0"
nom="Etape ${numetape} - Construction du nom d hote et du fichier resolv.conf"
verif
	if [ -d /home/stagiaire ]
	then
	echo "le compte stagiaire exist."
	else
	useradd -m stagiaire
	fi && \
vrai="0"
nom="Etape ${numetape} - Création du compte stagiaire"
verif
vrai="1"
	if [ "$prox" = "yes" ]
	then
		if [ "$auth" = "y" -o "$auth" = "Y" ]
		then
		profilproxyauth
		yumproxyauth
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
		yumproxy
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
vrai="0"
nom="Etape ${numetape} - Déclaration du proxy"
verif
#################################################
#     Liste des interface réseaux sur LB        #
#################################################
vrai="1"
clear
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
repok8s && \
selinuxSwap && \
vrai="0"
nom="Etape ${numetape} - Selection de l'interface réseau interne du LB"
verif
#################################################
#
# installation des applications.
#
#
vrai="1"
yum  install -y ${applb} && \
vrai="0"
nom="Etape ${numetape} - Installation des outils et services sur LB"
verif
#################################################
#
# Configuration du service NFS.
#
#
vrai="1"
nfsconfigserver && \
vrai="0"
nom="Etape ${numetape} - Configuration du service NFS"
verif
#################################################
#
# Configuration et démarrage du serveur BIND9 selon le rôle de chacuns.
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
sed -i -e "s|bad|$secret|g" /etc/named/ddns.key &&\
chown root:named /etc/named/ddns.key && \
chmod 640 /etc/named/ddns.key && \
sed -i -e "s|listen-on port 53 { 127.0.0.1; };|listen-on port 53 { 10.0.0.100; 127.0.0.1; };|g" /etc/named.conf &&\
sed -i -e "s|allow-query     { localhost; };|allow-query     { localhost;10.0.0.0/24; };|g" /etc/named.conf && \
echo 'OPTIONS="-4"' >> /etc/sysconfig/named && \
named && \
namedMonDom && \
chown root:named /var/named/mon.dom.db && \
chmod 660 /var/named/mon.dom.db && \
namedRevers && \
chown root:named /var/named/10.0.0.db && \
chmod 660 /var/named/10.0.0.db && \
systemctl enable --now named.service && \
vrai="0"
nom="Etape ${numetape} - Configuration et demarrage de bind"
verif
#################################################
#
# configuration du NAT sur LB
#
vrai="1"
firewall-cmd --permanent --add-masquerade && \
firewall-cmd --add-masquerade && \
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
systemctl enable  --now  dhcpd.service && \
vrai="0"
nom="Etape ${numetape} - Configuration et start du service dhcp"
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
# Installation du service docker-ce
#
#
vrai="1"
docker && \
vrai="0"
nom="Etape ${numetape} - Installation du service docker-ce"
verif
#############################################################
#                                                           #
#             Configuration du LB Nginx avec docker         #
#                                                           #
#############################################################
mkdir -p ~/nginx && cd ~/nginx
cat <<EOF> nginx.conf
worker_processes  1;
include /etc/nginx/modules-enabled/*.conf;
error_log  /var/log/nginx/error.log warn;
pid        /var/run/nginx.pid;

events {
    worker_connections  1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
	    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
		      '$status $body_bytes_sent "$http_referer" '
		      '"$http_user_agent" "$http_x_forwarded_for"';
	    access_log  /var/log/nginx/access.log  main;
	    sendfile        on;
    #tcp_nopush     on;
	    keepalive_timeout  65;
	    #gzip  on;
	    include /etc/nginx/conf.d/*.conf;
}
stream {
	upstream apiserver {
	    server master1-k8s.mon.dom:6443 weight=5 max_fails=3 fail_timeout=30s;
	    server master2-k8s.mon.dom:6443 weight=5 max_fails=3 fail_timeout=30s;
	    server master3-k8s.mon.dom:6443 weight=5 max_fails=3 fail_timeout=30s;
	    #server ${HOST_IP}:6443 weight=5 max_fails=3 fail_timeout=30s;
	    #server ${HOST_IP}:6443 weight=5 max_fails=3 fail_timeout=30s;
	}
	    server {
	listen 6443;
	proxy_connect_timeout 1s;
	proxy_timeout 3s;
	proxy_pass apiserver;
    }
}
EOF
cat <<EOF > Dockerfile
FROM nginx
add nginx.conf /etc/nginx/nginx.conf
EOF
#################################################
#
# Build de l'image bloby01/nginx-lb-multimaster:v1
#
#
vrai="1"
su -lc 'docker build -t bloby01/nginx-lb-multimaster:v1 /root/nginx/' && \
vrai="0"
nom="Etape ${numetape} - Build de l'image bloby01/nginx-lb-multimaster:v1"
verif
	if [ ${vrai} = "0" ]
	then
	echo " "
	echo " Fin de la première partie de déploiement du loadbalancer"
	echo " Déployez maintenant les noeuds masters"
	fi
############################################################################################
#                                                                                          #
#	                 Fin du Déploiement loadbalancer                                   #
#	                                                                                   #
############################################################################################
fi
if [ "${noeud}" = "master" ]
then
#################################################
#
# Configuration du nom du noeud + resolv.conf + SwapOFF + SELinux à permissive
#
#
vrai="1"
#x="0" ; until [ "${x}" -gt "0" -a "${x}" -lt "4" ] ; do echo -n "Mettez un numéro de ${noeud} à installer 1, 2 ou 3, pour ${noeud}1-k8s.mon.dom, mettre: 1 : " ; read x ; done
hostnamectl  set-hostname  ${HOST0} && \
export node="${noeud}" && \
export HOST="${HOST0}" && \
selinuxSwap && \
cat <<EOF > /etc/resolv.conf
options ndots:15 timeout:1 attempts:5
domain mon.dom
nameserver 10.0.0.100
nameserver 8.8.8.8
EOF
vrai="0"
nom="Etape ${numetape} - Configuration du nom du noeud + resolv.conf + SwapOFF + SELinux à permissive"
verif
###########################################################
#
#   Script en attente de démarrage des trois noeuds master
#
clear
echo " "
echo "#################################################################################"
echo "#		Assurez vous que les trois noeuds master soient démarré avant"
echo "#                    de passer à l'étape suivante."
echo " "
	until [ "${aa}" = "y" -o "${aa}" = "Y" ]
	do
	ping -c1 ${HOST0}
	ping -c1 ${HOST1}
	ping -c1 ${HOST2}
	echo " "
	echo -n "Vous confirmez voir la réponse au ping des trois noeuds? y/n: "
	read aa
	clear
	done
#################################################
#
# Création des clés pour ssh-copy-id
#
#
vrai="1"
rm -rf ~/.ssh/id_rsa*
ssh-keygen -b 4096 -t rsa -f ~/.ssh/id_rsa -P "" && \
	for i in ${HOST0} ${HOST1} ${HOST2}
	do
	ssh-copy-id -i ~/.ssh/id_rsa.pub root@${i}
	done
vrai="0"
nom="Etape ${numetape} - Création des clés pour ssh-copy-id."
verif
	for HOST in ${HOST0} ${HOST1} ${HOST2}
	do
	clear
	echo " Configuration de la machine ${HOST}"
		if [ "$prox" = "yes" ]
		then
			if [ "$auth" = "y" -o "$auth" = "Y" ]
			then
			profilproxyauth
			yumproxyauth
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
			yumproxy
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
	################################################
	#
	# installation du repository kubernetes.
	#
	#
	vrai="1"
	repok8s && \
	vrai="0"
	nom="Etape ${numetape} - Installation du repository kubernetes sur le master"
	verif
	################################################
	#
	# installation des applications.
	#
	#
	vrai="1"
	yum  install -y ${appmaster} && \
	vrai="0"
	nom="Etape ${numetape} - Installation des outils et services sur le master"
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
	nom="Etape ${numetape} - Démarrage de la kubelet"
	verif
	#################################################
	#
	# installation de docker
	#
	#
	vrai="1"
	docker && \
	vrai="0"
	nom="Etape ${numetape} - Configuration et installation du service docker-ce"
	verif
	done
#################################################
#
# Génération des certificats pour les noeuds master
#
#
vrai="1"
	if [ `hostname` = "${HOST0}" ]
	then
	HOST=${HOST0}
	#################################################
	#
	# Création du fichier de démarrage de service ETCD
	#                avec une priorité haute
	#
	vrai="1"
		if [ -d /etc/systemd/system/kubelet.service.d/ ]
		then
		echo "le dossier /etc/systemd/system/kubelet.service.d/ est présent. "
		else
		mkdir /etc/systemd/system/kubelet.service.d
		fi
  cat <<EOF> /etc/systemd/system/kubelet.service.d/20-etcd-service-manager.conf
	[Service]
	ExecStart=
	ExecStart=/usr/bin/kubelet --address=127.0.0.1 --pod-manifest-path=/etc/kubernetes/manifests
	Restart=always
EOF
	systemctl daemon-reload && \
	systemctl restart kubelet && \
	vrai="0"
	nom="Etape ${numetape} - Création du fichier de démarrage de service ETCD avec une priorité haute."
	verif
	#################################################
	#
	# Création d'un fichier de configuration pour chaque noeud membre ETCD
	#
	vrai="1"
	# Update HOST0, HOST1, and HOST2 with the IPs or resolvable names of your hosts
	#export HOST0=master1-k8s.mon.dom
	#export HOST1=master2-k8s.mon.dom
	#export HOST2=master3-k8s.mon.dom

	# Create temp directories to store files that will end up on other hosts.
	mkdir -p /tmp/${HOST0}/ /tmp/${HOST1}/ /tmp/${HOST2}/

	ETCDHOSTS=(${HOST0} ${HOST1} ${HOST2})
	NAMES=("infra0" "infra1" "infra2")

		for i in "${!ETCDHOSTS[@]}"; do
		HOST=${ETCDHOSTS[$i]}
		NAME=${NAMES[$i]}
		cat <<EOF> /tmp/${HOST}/kubeadmcfg.yaml
apiVersion: kubeadm.k8s.io/v1beta2
kind: ClusterConfiguration
kubernetesVersion: stable
apiServer:
 CertSANs:
 - 10.0.0.100
 - 10.0.0.110
 - 10.0.0.111
 - 10.0.0.112
 - 10.0.0.113
 - 10.0.0.114
 - 10.0.0.115
 - master1-k8s.mon.dom
 - master2-k8s.mon.dom
 - master3-k8s.mon.dom
 - loadbalancer-k8s.mon.dom
 - minion1-k8s.mon.dom
 - minion2-k8s.mon.dom
 - minion3-k8s.mon.dom
controlPlaneEndpoint: "loadbalancer-k8s.mon.dom:6443"
etcd:
 external:
  endpoints:
  - https://master1-k8s.mon.dom:2379
  - https://master2-k8s.mon.dom:2379
  - https://master3-k8s.mon.dom:2379
  caFile: /etc/kubernetes/pki/etcd/ca.crt
#  certFile: /etc/kubernetes/pki/etcd/server.crt
  keyFile: /etc/kubernetes/pki/etcd/ca.key
networking:
 podSubnet: 192.168.0.0/16
#apiServerExtraArgs:
# apiserver-count: "3"
#apiVersion: "kubeadm.k8s.io/v1beta1"
#kind: ClusterConfiguration
#etcd:
#    local:
#        serverCertSANs:
#        - "${HOST}"
#        peerCertSANs:
#        - "${HOST}"
#        extraArgs:
#            initial-cluster: ${NAMES[0]}=https://${ETCDHOSTS[0]}:2380,${NAMES[1]}=https://${ETCDHOSTS[1]}:2380,${NAMES[2]}=https://${ETCDHOSTS[2]}:2380
#            initial-cluster-state: new
#            name: ${NAME}
#            listen-peer-urls: https://${HOST}:2380
#            listen-client-urls: https://${HOST}:2379
#            advertise-client-urls: https://${HOST}:2379
#            initial-advertise-peer-urls: https://${HOST}:2380
EOF
		done && \
	vrai="0"
	nom="Etape ${numetape} - Création d'un fichier de configuration pour chaque noeud membre ETCD."
	verif
	#################################################
	#
	# Création CA et certificats pour ETCD
	#
	#
	#vrai="1"
	kubeadm init phase certs etcd-ca && \
echo " " ; echo "Faire Entree pour continuer" ;read tt
	kubeadm init phase certs etcd-server --config=/tmp/${HOST2}/kubeadmcfg.yaml && \
echo " " ; echo "Faire Entree pour continuer" ;read tt
	kubeadm init phase certs etcd-peer --config=/tmp/${HOST2}/kubeadmcfg.yaml && \
echo " " ; echo "Faire Entree pour continuer" ;read tt
	kubeadm init phase certs etcd-healthcheck-client --config=/tmp/${HOST2}/kubeadmcfg.yaml && \
echo " " ; echo "Faire Entree pour continuer" ;read tt
	kubeadm init phase certs apiserver-etcd-client --config=/tmp/${HOST2}/kubeadmcfg.yaml && \
echo " " ; echo "Faire Entree pour continuer" ;read tt
	cp -R /etc/kubernetes/pki /tmp/${HOST2}/ && \
	# cleanup non-reusable certificates
echo " " ; echo "Faire Entree pour continuer" ;read tt
	find /etc/kubernetes/pki -not -name ca.crt -not -name ca.key -type f -delete && \
echo " " ; echo "Faire Entree pour continuer" ;read tt
	kubeadm init phase certs etcd-server --config=/tmp/${HOST1}/kubeadmcfg.yaml && \
echo " " ; echo "Faire Entree pour continuer" ;read tt
	kubeadm init phase certs etcd-peer --config=/tmp/${HOST1}/kubeadmcfg.yaml && \
echo " " ; echo "Faire Entree pour continuer" ;read tt
	kubeadm init phase certs etcd-healthcheck-client --config=/tmp/${HOST1}/kubeadmcfg.yaml && \
echo " " ; echo "Faire Entree pour continuer" ;read tt
	kubeadm init phase certs apiserver-etcd-client --config=/tmp/${HOST1}/kubeadmcfg.yaml && \
echo " " ; echo "Faire Entree pour continuer" ;read tt
	cp -R /etc/kubernetes/pki /tmp/${HOST1}/ && \
echo " " ; echo "Faire Entree pour continuer" ;read tt
	find /etc/kubernetes/pki -not -name ca.crt -not -name ca.key -type f -delete && \
echo " " ; echo "Faire Entree pour continuer" ;read tt
	kubeadm init phase certs etcd-server --config=/tmp/${HOST0}/kubeadmcfg.yaml && \
echo " " ; echo "Faire Entree pour continuer" ;read tt
	kubeadm init phase certs etcd-peer --config=/tmp/${HOST0}/kubeadmcfg.yaml && \
echo " " ; echo "Faire Entree pour continuer" ;read tt
	kubeadm init phase certs etcd-healthcheck-client --config=/tmp/${HOST0}/kubeadmcfg.yaml && \
echo " " ; echo "Faire Entree pour continuer" ;read tt
	kubeadm init phase certs apiserver-etcd-client --config=/tmp/${HOST0}/kubeadmcfg.yaml && \
	# No need to move the certs because they are for HOST0
echo " " ; echo "Faire Entree pour continuer" ;read tt
	# clean up certs that should not be copied off this host
	find /tmp/${HOST2} -name ca.key -type f -delete && \
echo " " ; echo "Faire Entree pour continuer" ;read tt
	find /tmp/${HOST1} -name ca.key -type f -delete && \
echo " " ; echo "Derniere étape de verification" ; echo "Faire Entree pour continuer" ;read tt
	vrai="0"
	nom="Etape ${numetape} - Création CA et certificats pour ETCD."
	verif
	####################################################
	#
	# Copie des certificats dans les noeuds master ETCD
	#
	#
		for HOST in ${HOST0} ${HOST1} ${HOST2}
		do
		vrai="1"
		USER=root
		#HOST=${HOST1}
		scp -r /tmp/${HOST}/* ${USER}@${HOST}:.
		ssh ${USER}@${HOST} chown -R root:root pki
		ssh ${USER}@${HOST} mv pki /etc/kubernetes/
		done
	vrai="0"
	nom="Etape ${numetape} - Copie des certificats dans les noeuds master ETCD."
	verif
	#############################################################
	#
	# Création des manifests de pods dans les noeuds master ETCD
	#
	#
	vrai="1"
	ssh root@HOST0 kubeadm init phase etcd local --config=/root/kubeadmcfg.yaml && \
	ssh root@HOST1 kubeadm init phase etcd local --config=/root/kubeadmcfg.yaml && \
	ssh root@HOST2 kubeadm init phase etcd local --config=/root/kubeadmcfg.yaml && \
	vrai="0"
	nom="Etape ${numetape} - Création des manifests de pods dans les noeuds master ETCD."
	verif
	#############################################################
	#
	# Vérification de l'état de santée du cluster ETCD
	#
	#
	vrai="1"
	docker run --rm -it \
	--net host \
	-v /etc/kubernetes:/etc/kubernetes quay.io/coreos/etcd:${ETCD_TAG} etcdctl \
	--cert-file /etc/kubernetes/pki/etcd/peer.crt \
	--key-file /etc/kubernetes/pki/etcd/peer.key \
	--ca-file /etc/kubernetes/pki/etcd/ca.crt \
	--endpoints https://${HOST0}:2379 cluster-health
	echo " "
	echo "Faire entrée pour continuer ou contrôle C pour arréter."
	read tt && \
	vrai="0"
	nom="Etape ${numetape} - Vérification de l'état de santée du cluster ETCD."
	verif
	#################################################
	#
	# Création CA et certificats pour les liaisons TLS
	#
	#
	#vrai="1"
	#mkdir -p ~/k8s/crt ~/k8s/key ~/k8s/csr
	#cat <<EOF> ~/k8s/openssl.cnf
	#[ req ]
	#distinguished_name = req_distinguished_name
	#[req_distinguished_name]
	#[ v3_ca ]
	#basicConstraints = critical, CA:TRUE
	#keyUsage = critical, digitalSignature, keyEncipherment, keyCertSign
	#[ v3_req_etcd ]
	#basicConstraints = CA:FALSE
	#keyUsage = critical, digitalSignature, keyEncipherment
	#extendedKeyUsage = serverAuth, clientAuth
	#subjectAltName = @alt_names_etcd
	#[ alt_names_etcd ]
	#DNS.1 = master1-k8s.mon.dom
	#DNS.2 = master2-k8s.mon.dom
	#DNS.3 = master3-k8s.mon.dom
	#IP.1 = `nslookup master1-k8s.mon.dom | tail -2 | cut -f 2 -d " "`
	#IP.2 = `nslookup master2-k8s.mon.dom | tail -2 | cut -f 2 -d " "`
	#IP.3 = `nslookup master3-k8s.mon.dom | tail -2 | cut -f 2 -d " "`
	#EOF
	#openssl genrsa -out ~/k8s/key/etcd-ca.key 4096
	#openssl req -x509 -new -sha256 -nodes -key ~/k8s/key/etcd-ca.key -days 3650 -out ~/k8s/crt/etcd-ca.crt -subj "/CN=etcd-ca" -extensions v3_ca -config ~/k8s/openssl.cnf
	#openssl genrsa -out ~/k8s/key/etcd.key 4096
	#openssl req -new -sha256 -key ~/k8s/key/etcd.key -subj "/CN=etcd" -out ~/k8s/csr/etcd.csr
	#openssl x509 -req -in ~/k8s/csr/etcd.csr -sha256 -CA ~/k8s/crt/etcd-ca.crt -CAkey ~/k8s/key/etcd-ca.key -CAcreateserial -out ~/k8s/crt/etcd.crt -days 365 -extensions v3_req_etcd -extfile ~/k8s/openssl.cnf
	#openssl genrsa -out ~/k8s/key/etcd-peer.key 4096
	#openssl req -new -sha256 -key ~/k8s/key/etcd-peer.key -subj "/CN=etcd-peer" -out ~/k8s/csr/etcd-peer.csr
	#openssl x509 -req -in ~/k8s/csr/etcd-peer.csr -sha256 -CA ~/k8s/crt/etcd-ca.crt -CAkey ~/k8s/key/etcd-ca.key -CAcreateserial -out ~/k8s/crt/etcd-peer.crt -days 365 -extensions v3_req_etcd -extfile ~/k8s/openssl.cnf
	#vrai="0"
	#nom="Etape ${numetape} - Création CA et certificats pour les liaisons TLS"
	#verif

	fi
#################################################
#
#  Construction de l'ETCD dans chacun des trois noeuds.
#
#
#vrai="1"
#ETCD_VER=v3.3.25 && \
#GOOGLE_URL=https://storage.googleapis.com/etcd && \
#GITHUB_URL=https://github.com/coreos/etcd/releases/download && \
#DOWNLOAD_URL=${GOOGLE_URL} && \
#mkdir ~/etcd_${ETCD_VER} && \
#cd ~/etcd_${ETCD_VER} && \
#cat <<EOF>etcd_${ETCD_VER}-install.sh
#curl -L ${DOWNLOAD_URL}/${ETCD_VER}/etcd-${ETCD_VER}-linux-amd64.tar.gz -o etcd-${ETCD_VER}-linux-amd64.tar.gz
#tar xzvf etcd-${ETCD_VER}-linux-amd64.tar.gz -C .
#EOF
#chmod +x etcd_${ETCD_VER}-install.sh && \
#./etcd_${ETCD_VER}-install.sh && \


#cd ~
	#for master in master1-k8s.mon.dom master2-k8s.mon.dom master3-k8s.mon.dom; do \
	#cat <<EOF>~/etcd.service
	#[Unit]
	#Description=etcd
	#Documentation=https://github.com/coreos

	#[Service]
	#ExecStart=/usr/local/bin/etcd \\
	#  --name ${master} \\
	#  --cert-file=/etc/etcd/pki/etcd.crt \\
	#  --key-file=/etc/etcd/pki/etcd.key \\
	#  --peer-cert-file=/etc/etcd/pki/etcd-peer.crt \\
	#  --peer-key-file=/etc/etcd/pki/etcd-peer.key \\
	#  --trusted-ca-file=/etc/etcd/pki/etcd-ca.crt \\
	#  --peer-trusted-ca-file=/etc/etcd/pki/etcd-ca.crt \\
	#  --peer-client-cert-auth \\
	#  --client-cert-auth \\
	#  --initial-advertise-peer-urls https://${master}:2380 \\
	#  --listen-peer-urls https://${master}:2380 \\
	#  --listen-client-urls https://${master}:2379,http://127.0.0.1:2379 \\
	#  --advertise-client-urls https://${master}:2379 \\
	#  --initial-cluster-token etcd-cluster-0 \\
	#  --initial-cluster master1-k8s.mon.dom=https://master1-k8s.mon.dom:2380,master2-k8s.mon.dom=https://master2-k8s.mon.dom:2380,master3-k8s.mon.dom=https://master3-k8s.mon.dom:2380 \\
	#  --data-dir=/var/lib/etcd
	#  --initial-cluster-state=new
	#Restart=on-failure
	#RestartSec=5
	#
	#[Install]
	#WantedBy=multi-user.target
	#EOF
	#ssh ${master} "test -d /etc/etcd/pki && rm -rf /etc/etcd/pki" ; \
	#ssh ${master} "test -d /var/lib/etcd && rm -rf /var/lib/etcd" ; \
	#ssh ${master} "mkdir -p /etc/etcd/pki ; mkdir -p /var/lib/etcd" ;  \
	#scp ~/k8s/crt/etcd* ~/k8s/key/etcd* ${master}:/etc/etcd/pki/;  \
	#scp etcd.service ${master}:/etc/systemd/system/etcd.service ; \
	#scp ~/etcd_${ETCD_VER}/etcd-${ETCD_VER}-linux-amd64/etcd ${master}:/usr/local/bin; \
	#scp ~/etcd_${ETCD_VER}/etcd-${ETCD_VER}-linux-amd64/etcdctl ${master}:/usr/local/bin;
	#done

	#for master in master1-k8s.mon.dom master2-k8s.mon.dom master3-k8s.mon.dom; do \
	#ssh  ${master} "systemctl daemon-reload" ; \
	#ssh ${master} "systemctl enable --now etcd" ;
	#done
#vrai="0"
#nom="Etape ${numetape} - Déploiement et démarrage du service ETCD sur chaque noeud master"
#verif
#################################################
#
# Vérification du fonctionnement des services ETCD
#
#
#clear
#echo "###################################################################################"
#echo " " ; echo " "
#echo "Affiche l'état des noeuds master du cluster"
#etcdctl --ca-file /etc/etcd/pki/etcd-ca.crt --cert-file /etc/etcd/pki/etcd.crt --key-file /etc/etcd/pki/etcd.key cluster-health
#echo " " ; echo " "
#echo "Affiche les membres master et le status <LEADER> pour un noeud"
#etcdctl --ca-file /etc/etcd/pki/etcd-ca.crt --cert-file /etc/etcd/pki/etcd.crt --key-file /etc/etcd/pki/etcd.key member list
#echo " "
#echo "Faire entrée pour continuer."
#read tt
#################################################
#
# deployement des masters
#
#
#vrai="1"
	#if [ `hostname` = "master1-k8s.mon.dom" ]
	#then
	#cat <<EOF>~/kubeadm-init.yaml
	#apiVersion: kubeadm.k8s.io/v1beta2
	#kind: ClusterConfiguration
	#kubernetesVersion: stable
	#apiServer:
	# CertSANs:
	# - 10.0.0.100
	# - 10.0.0.110
	# - 10.0.0.111
	# - 10.0.0.112
	# - 10.0.0.113
	# - 10.0.0.114
	# - 10.0.0.115
	# - master1-k8s.mon.dom
	# - master2-k8s.mon.dom
	# - master3-k8s.mon.dom
	# - loadbalancer-k8s.mon.dom
	# - minion1-k8s.mon.dom
	# - minion2-k8s.mon.dom
	# - minion3-k8s.mon.dom
	#controlPlaneEndpoint: "loadbalancer-k8s.mon.dom:6443"
	#etcd:
	#  external:
	#    endpoints:
	#    - https://master1-k8s.mon.dom:2379
	#    - https://master2-k8s.mon.dom:2379
	#    - https://master3-k8s.mon.dom:2379
	#    caFile: /etc/etcd/pki/etcd-ca.crt
	#    certFile: /etc/etcd/pki/etcd.crt
	#    keyFile: /etc/etcd/pki/etcd.key
	#networking:
	#  podSubnet: 192.168.0.0/16
	#apiServerExtraArgs:
	#  apiserver-count: "3"
	#EOF
	#
		#if [ -d /home/kubeadmin ]
		#then
		#userdel -r kubeadmin
		#useradd -m -s /bin/bash -G wheel,docker kubeadmin
		#else
		#useradd -m -s /bin/bash -G wheel,docker kubeadmin
		#fi
	#kubeadm init --config=kubeadm-init.yaml
	#vrai="0"
	#nom="Etape ${numetape} - Deploiement du cluster K8S sur le premier master"
	#verif
	#fi
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
nom="Etape ${numetape} - Installation de calico"
verif
################################################
#
# Déploiement du persistentVolumeDynamique sur le cluster
#
#
#vrai="1"
#githelm  && \
#vrai="0"
#nom="Etape ${numetape} - Déploiement du persistentVolumeDynamique sur le cluster"
#verif
#####################################################################
#                                                                   #
#                     Fin de la configuration master                #
#                                                                   #
#####################################################################


############################################################################################
#                                                                                          #
#                       Déploiement des workers Kubernetes                                 #
#                                                                                          #
############################################################################################
fi
if [ "${noeud}" = "worker" ]
then
#################################################
#
# Configuration du nom du noeud
#
#
vrai="1"
x="0" ; until [ "${x}" -gt "0" -a "${x}" -lt "4" ] ; do echo -n "Mettez un numéro de ${noeud} à installer 1, 2 ou 3, pour ${noeud}1-k8s.mon.dom, mettre: 1 : " ; read x ; done
hostnamectl  set-hostname  ${noeud}${x}-k8s.mon.dom && \
export node="${noeud}"
vrai="0"
nom="Etape ${numetape} - Configuration du nom du noeud"
verif
	if [ "$prox" = "yes" ]
	then
		if [ "$auth" = "y" -o "$auth" = "Y" ]
		then
		profilproxyauth
		yumproxyauth
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
		yumproxy
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
vrai="1"
systemctl restart NetworkManager && \
vrai="0"
nom="Etape ${numetape} - Restart de la pile réseau du worker"
verif
#################################################
#
# Création des clés pour ssh-copy-id
#
#
vrai="1"
ssh-keygen -b 4096 -t rsa -f ~/.ssh/id_rsa -P "" && \
ssh-copy-id -i ~/.ssh/id_rsa.pub root@master1-k8s.mon.dom && \
vrai="0"
nom="Etape ${numetape} - Configuration du ssh agent"
verif
#################################################
#
# récuparation du token d'intégration et du hash sha256 du certificat CA
#
#
vrai="1"
alias leader="ssh root@master1-k8s.mon.dom" && \
export token=`leader kubeadm token list | tail -1 | cut -f 1,2 -d " "` && \
tokensha=`leader openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //'` && \
export tokenca=sha256:${tokensha} && \
vrai="0"
nom="Etape ${numetape} - Recuperation des clés sur le master pour l'intégration au cluster"
verif
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
# Gestion du SELinux et suppression du swap
#
#
vrai="1"
selinuxSwap && \
vrai="0"
nom="Etape ${numetape} - Configuration du SELINUX"
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
# Chargement du module noyau de bridge
#
#
vrai="1"
moduleBr && \
sysctl   -w net/ipv4/ip_forward=1 && \
cat <<EOF >> /etc/sysctl.conf
net/ipv4/ip_forward=1
EOF
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
nom="Etape ${numetape} - Installation du service docker sur le worker"
verif
#################################################
#
# Jonction de l'hôte au cluster
#
#
vrai="1"
kubeadm join master-k8s.mon.dom:6443 --token ${token}  --discovery-token-ca-cert-hash ${tokenca} && \
vrai="0"
nom="Etape ${numetape} - Intégration du noeud worker au cluster"
verif
fi
