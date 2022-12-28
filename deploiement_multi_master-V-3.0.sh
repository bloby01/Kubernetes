#!/bin/bash
#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!								                                                	!!!
#   !!!		           ATTENTION		                           !!!
#   !!!			                                                   !!!
#   !!!		   Vérifier le proxy avec login et password (non testé)    !!!
#   !!!		                                                           !!!
# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
#   Version script: 3.0
#   Deploiement sur Rocky Linux 9 minimum
#   Version kubelet: 1.26 +
#   Version Containerd	: 1.6.14
#   Version RunC 	: 1.1.4
#   Version CNI-Plugin	: 1.1.1
#   Version calico	: 3.24.0
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
# - Le système sur lequel s'exécute ce script doit être un Rocky Linux 9.0 & +  #
# - Le compte root doit etre utilisé pour exécuter ce Script                    #
# - Le script requière :		        				#
#	*  L'outil vitualbox (le cluster fonctionne dans un réseau privé)       #
#	*  Le loadBalancer à deux interface réseaux :			        #
#		- La première en bridge/dhcp				        #
#       	- La seconde dans le réseau privé est attendu à 172.21.0.100/24 #
#   	*  Les adresses/noms des noeuds sont automatiquement attribuées		#
# - Le réseau overlay est gérer par VxLAN à l'aide de Calico                     #
# - Les systèmes sont synchronisés sur le serveur de temps zone Europe/Paris    #
# - Les services NAMED et DHCPD sont installés sur le loadBalancer		#
# - Le LABS est établie avec un maximum de 3 noeuds masters & 6 noeuds workers  #
# - L'API est joignable par le loadBalancer sur l'adresse 172.21.0.100:6443     #
# - Un service de proxy cache est présent sur la machine loadbalancer		#
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
appmaster="wget tar bind-utils nfs-utils kubelet iproute-tc kubeadm kubectl --disableexcludes=kubernetes"
appworker="wget tar bind-utils nfs-utils kubelet iproute-tc kubeadm --disableexcludes=kubernetes"
appHAProxy="wget haproxy bind bind-utils iproute-tc policycoreutils-python-utils dhcp-server squid"
printf -v IpCalico '%s,' 192.168.{0..31}.{0..255}
printf -v IpCluster '%s,' 172.21.0.{0..255}
NoProxyAdd=".cluster.local,${IpCalico}.mon.dom,${IpCluster}localhost,127.0.0.1"
#NoProxyAdd=".cluster.local,${IpCalico}.mon.dom,172.21.0.1,172.21.0.2,172.21.0.3,172.21.0.100,172.21.0.101,172.21.0.102,172.21.0.103,172.21.0.104,172.21.0.105,172.21.0.106,172.21.0.107,172.21.0.108,172.21.0.109,172.21.0.110,172.21.0.111,172.21.0.112,172.21.0.113,localhost,127.0.0.1"
VersionContainerD="1.6.14"
VersionRunC="1.1.4"
VersionCNI="1.1.1"
VersionCalico="3.22.0"
proxy="http://loadbalancer-k8s.mon.dom:3128/"
NoProxy="${NoProxyAdd}"

#                                                                               	  #
###########################################################################################
#                                                                               	  #
#                      Déclaration des fonctions                                	  #
#                                                                               	  #
###########################################################################################
#Fonction de creation du fichier /etc/environment
#
environmentProxy(){
echo $NoProxyAdd > /etc/environment
}

#Fonction d'installation du repo pour Kubernetes
repok8s(){
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-\$basearch
enabled=1
gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kubelet kubeadm kubectl
EOF
}

#Fonction de vérification des étapes
verif(){
numetape=`expr ${numetape} + 1 `
  if [ "${vrai}" -eq "0" ]; then
    echo "Machine: ${node}${x}-k8s.mon.dom - ${nom} - OK"
  else
    echo "Erreur sur Machine: ${node}${x}-k8s.mon.dom - ${nom} - OUPSSS "
    exit 0
  fi
}
# Fonction d'installation de containerd en derniere version stable
containerd(){
vrai="1"
wget  https://github.com/containerd/containerd/releases/download/v${VersionContainerD}/containerd-${VersionContainerD}-linux-amd64.tar.gz && \
tar Cxzf /usr/local/ containerd-${VersionContainerD}-linux-amd64.tar.gz && \
mkdir -p /usr/local/lib/systemd/system/
cat <<EOF > /usr/local/lib/systemd/system/containerd.service
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
wget https://github.com/opencontainers/runc/releases/download/v${VersionRunC}/runc.amd64 && \
install -m  755 runc.amd64  /usr/local/bin/runc && \
wget https://github.com/containernetworking/plugins/releases/download/v${VersionCNI}/cni-plugins-linux-amd64-v${VersionCNI}.tgz && \
mkdir -p /opt/cni/bin && \
tar Cxzf /opt/cni/bin/ cni-plugins-linux-amd64-v${VersionCNI}.tgz && \
nom="Déploiement de containerd, RUNC et CNI plugin sur le noeud"
vrai="0"
verif
}

# Fonction de configuration des parametres communs du dhcp
dhcp(){
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
named(){
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
namedMonDom(){
vrai="1"
cat <<EOF > /var/named/mon.dom.db
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
vrai="0"
nom="Configuration du fichier de zone mondom.db"
}

# Fonction de configuration de la zone reverse named
namedRevers(){
vrai="1"
cat <<EOF > /var/named/172.21.0.db
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
vrai="0"
nom="Configuration du fichier de zone 0.21.172.in-addr.arpa.db"
}

# Fonction de configuration du repo k8s
repok8s(){
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
Swap(){
vrai="1"
swapoff   -a && \
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab && \
vrai="0"
nom="Désactivation du Swap"
}

# Fonction de configuration du module bridge
moduleBr(){
vrai="1"
modprobe  br_netfilter && \
cat <<EOF > /etc/rc.modules
modprobe  br_netfilter
EOF
chmod  +x  /etc/rc.modules && \
sysctl   -w net.bridge.bridge-nf-call-iptables=1 && \
sysctl   -w net.bridge.bridge-nf-call-ip6tables=1 && \
sysctl -w net.ipv4.ip_forward=1 && \
cat <<EOF > /etc/sysctl.conf
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
net.ipv4.ip_forward=1
EOF
vrai="0"
nom="Configuration du module br_netfilter et routage IP"
}

# Fonction de serveur de temps
temps(){
vrai="1"
timedatectl set-timezone "Europe/Paris" && \
timedatectl set-ntp true && \
vrai="0"
nom="Configuration du serveur de temps"
}

# Fonction  de configuration de profil avec proxy auth
profilproxyauth(){
vrai="1"
cat <<EOF > /etc/profile
export HTTP_PROXY="http://${proxyLogin}:${proxyPassword}@${proxyUrl}"
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
dnfproxyauth(){
vrai="1"
cat <<EOF >> /etc/dnf/dnf.conf
proxy="${proxyUrl}"
proxy_username=${proxyLogin}
proxy_password=${proxyPassword}
EOF
vrai="0"
nom="Configuration de yum avec proxy auth"
}

# Fonction  de configuration de profil avec proxy
profilproxy(){
vrai="1"
cat <<EOF >> /etc/profile
export HTTP_PROXY="${proxy}"
export HTTPS_PROXY="${proxy}"
export http_proxy="${proxy}"
export https_proxy="${proxy}"
export no_proxy="${NoProxy}"
export NO_PROXY="${NoProxy}"
EOF
vrai="0"
nom="Configuration du fichier /etc/profil avec proxy"
}
# Fonction  de configuration du shell bash avec proxy
bashproxy(){
vrai="1"
cat <<EOF >> ~/.bashrc
export HTTP_PROXY="${proxy}"
export HTTPS_PROXY="${proxy}"
export http_proxy="${proxy}"
export https_proxy="${proxy}"
export no_proxy="${NoProxy}"
export NO_PROXY="${NoProxy}"
EOF
vrai="0"
nom="Configuration du fichier /etc/profil avec proxy"
}

# Fonction de configuration de dnf avec proxy
dnfproxy(){
vrai="1"
cat <<EOF >> /etc/dnf/dnf.conf
proxy="${proxy}"
EOF
vrai="0"
nom="Configuration de DNF avec proxy"
}

# Fonction de création des clés pour ssh-copy-id
#
CopyIdRoot(){
#
#ssh-keygen -b 4096 -t rsa -f ~/.ssh/id_rsa -P ""
ssh-copy-id -i ~/.ssh/id_rsa.pub root@master1-k8s.mon.dom
}
CopyIdLB(){
#
ssh-keygen -b 4096 -t rsa -f ~/.ssh/id_rsa -P ""
ssh-copy-id -i ~/.ssh/id_rsa.pub root@loadBalancer-k8s.mon.dom
}


# Fonction de récupération du token et sha253 de cacert
#
RecupToken(){
alias master1="ssh root@master1-k8s.mon.dom"
scp root@master1-k8s.mon.dom:noeudsupplementaires.txt ~/.
if [ -d ~/.kube ]
then
scp root@master1-k8s.mon.dom:/etc/kubernetes/admin.conf ~/.kube/config
else
mkdir ~/.kube
scp root@master1-k8s.mon.dom:/etc/kubernetes/admin.conf ~/.kube/config
fi
export KUBECONFIG=~/.kube/config
export token=$(grep token ~/noeudsupplementaires.txt | head -1 | cut -f 4 -d " ")
export CertsKey=$(grep certificate-key ~/noeudsupplementaires.txt | head -1)
export tokencaworker=`master1 openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //'`
export tokensha=`master1 openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //'`
}
configWget(){
cat <<EOF > /etc/wgetrc
###
### Sample Wget initialization file .wgetrc
###
## You can use this file to change the default behaviour of wget or to
## avoid having to type many many command-line options. This file does
## not contain a comprehensive list of commands -- look at the manual
## to find out what you can put into this file. You can find this here:
##   $ info wget.info 'Startup File'
## Or online here:
##   https://www.gnu.org/software/wget/manual/wget.html#Startup-File
##
## Wget initialization file can reside in /etc/wgetrc
## (global, for all users) or $HOME/.wgetrc (for a single user).
##
## To use the settings in this file, you will have to uncomment them,
## as well as change them, in most cases, as the values on the
## commented-out lines are the default values (e.g. "off").
##
## Command are case-, underscore- and minus-insensitive.
## For example ftp_proxy, ftp-proxy and ftpproxy are the same.
##
## Global settings (useful for setting up in /etc/wgetrc).
## Think well before you change them, since they may reduce wget's
## functionality, and make it behave contrary to the documentation:
##
# You can set retrieve quota for beginners by specifying a value
# optionally followed by 'K' (kilobytes) or 'M' (megabytes).  The
# default quota is unlimited.
#quota = inf
# You can lower (or raise) the default number of retries when
# downloading a file (default is 20).
#tries = 20
# Lowering the maximum depth of the recursive retrieval is handy to
# prevent newbies from going too "deep" when they unwittingly start
# the recursive retrieval.  The default is 5.
#reclevel = 5
# By default Wget uses "passive FTP" transfer where the client
# initiates the data connection to the server rather than the other
# way around.  That is required on systems behind NAT where the client
# computer cannot be easily reached from the Internet.  However, some
# firewalls software explicitly supports active FTP and in fact has
# problems supporting passive transfer.  If you are in such
# environment, use "passive_ftp = off" to revert to active FTP.
#passive_ftp = off
# The "wait" command below makes Wget wait between every connection.
# If, instead, you want Wget to wait only between retries of failed
# downloads, set waitretry to maximum number of seconds to wait (Wget
# will use "linear backoff", waiting 1 second after the first failure
# on a file, 2 seconds after the second failure, etc. up to this max).
#waitretry = 10
##
## Local settings (for a user to set in his $HOME/.wgetrc).  It is
## *highly* undesirable to put these settings in the global file, since
## they are potentially dangerous to "normal" users.
##
## Even when setting up your own ~/.wgetrc, you should know what you
## are doing before doing so.
##
# Set this to on to use timestamping by default:
#timestamping = off
# It is a good idea to make Wget send your email address in a From:
# header with your request (so that server administrators can contact
# you in case of errors).  Wget does *not* send From: by default.
#header = From: Your Name <username@site.domain>
# You can set up other headers, like Accept-Language.  Accept-Language
# is *not* sent by default.
#header = Accept-Language: en
# You can set the default proxies for Wget to use for http, https, and ftp.
# They will override the value in the environment.
https_proxy = http://loadBalancer-k8s.mon.dom:3128/
http_proxy = http://loadBalancer-k8s.mon.dom:3128/
ftp_proxy = http://loadBalancer-k8s.mon.dom:3128/
#https_proxy = http://proxy.yoyodyne.com:18023/
#http_proxy = http://proxy.yoyodyne.com:18023/
#ftp_proxy = http://proxy.yoyodyne.com:18023/
# If you do not want to use proxy at all, set this to off.
#use_proxy = on
# You can customize the retrieval outlook.  Valid options are default,
# binary, mega and micro.
#dot_style = default
# Setting this to off makes Wget not download /robots.txt.  Be sure to
# know *exactly* what /robots.txt is and how it is used before changing
# the default!
#robots = on
# It can be useful to make Wget wait between connections.  Set this to
# the number of seconds you want Wget to wait.
#wait = 0
# You can force creating directory structure, even if a single is being
# retrieved, by setting this to on.
#dirstruct = off
# You can turn on recursive retrieving by default (don't do this if
# you are not sure you know what it means) by setting this to on.
#recursive = off
# To always back up file X as X.orig before converting its links (due
# to -k / --convert-links / convert_links = on having been specified),
# set this variable to on:
#backup_converted = off
# To have Wget follow FTP links from HTML files by default, set this
# to on:
#follow_ftp = off
# To try ipv6 addresses first:
#prefer-family = IPv6
# Set default IRI support state
#iri = off
# Force the default system encoding
#localencoding = UTF-8
# Force the default remote server encoding
#remoteencoding = UTF-8
# Turn on to prevent following non-HTTPS links when in recursive mode
#httpsonly = off
# Tune HTTPS security (auto, SSLv2, SSLv3, TLSv1, PFS)
#secureprotocol = auto
EOF
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
if [ "${noeud}" = "worker" ]
then
vrai="1"
x=0 ; until [ "${x}" -gt "0" -a "${x}" -lt "7" ] ; do echo -n "Mettez un numéro de ${noeud} à installer (1 à 6 ... pour ${noeud}1-k8s.mon.dom, mettre: 1 ): " ; read x ; done
hostnamectl  set-hostname  ${noeud}${x}-k8s.mon.dom
systemctl restart NetworkManager
export node="worker"
elif [ ${noeud} = "master" ]
then
vrai="1"
x=0 ; until [ "${x}" -gt "0" -a "${x}" -lt "4" ] ; do echo -n "Mettez un numéro de ${noeud} à installer (1 à 3 ... pour ${noeud}1-k8s.mon.dom, mettre: 1 ): " ; read x ; done
hostnamectl  set-hostname  ${noeud}${x}-k8s.mon.dom
systemctl restart NetworkManager
export node="master"
	if [ "${noeud}${x}-k8s.mon.dom" = "master1-k8s.mon.dom" ]
	then 
	first="yes"
	else
	first="no"
	fi
elif [ ${noeud} = "loadBalancer" ]
then
vrai="1"
hostnamectl  set-hostname  loadBalancer-k8s.mon.dom
export node="loadBalancer"
#vrai="0"
#nom="Etape ${numetape} - Construction du nom d hote"
#verif
#fi
#vrai="1"
t=0 ; until [ "${t}" = "y" -o "${t}" = "Y" -o "${t}" = "n" -o "${t}" = "N" ] ; do echo -n "Y a t il un serveur proxy pour sortir du réseau ? Y/N : " ; read t ; done
if [ "$t" = "y" -o "$t" = "Y" ]
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
vrai="0"
nom="Etape ${numetape} - Configuration liaison au proxy  ok"
verif
fi
vrai="0"
nom="Etape ${numetape} - Construction du nom d hote"
verif
fi


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
#                       Déploiement du LB  HAProxy                                         #
#                                                                                          #
############################################################################################
if [ ${node} = "loadBalancer" ]
then
vrai="1"
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
  fi && \
vrai="0" && \
nom="Etape ${numetape} - Configuration de l'accès avec proxy ok"
verif
clear
#################################################
# 
# Présentation des interfaces réseaux disponibles
#
#
vrai="1"
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
nom="Etape ${numetape} - Choix de l'interface interne ok "
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
################################################
#
# demarrage du service squid cache
#
#
vrai="1"
systemctl enable --now squid  && \
vrai="0"
nom="Demarrage de squid cache  OK"
verif

#################################################
# 
# Configuration et démarrage du serveur BIND9.
#
#
vrai="1"
#dnssec-keygen -a HMAC-MD5 -b 128 -r /dev/urandom -n USER DDNS_UPDATE && \
dnssec-keygen -a RSASHA512 -b 2048 DDNS_UPDATE && \
cat <<EOF > /etc/named/ddns.key
key DDNS_UPDATE {
	algorithm hmac-sha512;
  secret "bad" ;
};
EOF
secret=`grep PrivateExponent: ./*.private | cut -f 2 -d " "` && \
sed -i -e "s|bad|$secret|g" /etc/named/ddns.key && \
chown named:dhcpd /etc/named/ddns.key && \
chmod 640 /etc/named/ddns.key && \
sed -i -e "s|listen-on port 53 { 127.0.0.1; };|listen-on port 53 { 172.21.0.100; 127.0.0.1; };|g" /etc/named.conf && \
sed -i -e "s|allow-query     { localhost; };|allow-query     { any; };|g" /etc/named.conf && \
echo 'OPTIONS="-4"' >> /etc/sysconfig/named && \
named && \
namedMonDom && \
chown named:named /var/named/mon.dom.db && \
chmod 660 /var/named/mon.dom.db && \
namedRevers && \
chown named:named /var/named/172.21.0.db && \
chmod 660 /var/named/172.21.0.db && \
semanage permissive -a named_t && \
named-compilezone -f text -F raw -o 172.21.0.db.raw 0.21.172.in-addr.arpa /var/named/172.21.0.db && \
named-compilezone -f text -F raw -o mon.dom.db.raw mon.dom /var/named/mon.dom.db && \
systemctl enable --now named.service && \
vrai="0"
nom="Etape ${numetape} - Configuration et demarrage de bind"
verif

#################################################
# 
# Configuration du LB HAProxy
#
#
vrai="1"
cat <<EOF > /etc/haproxy/haproxy.cfg
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

# installation des paramètres sur les noeuds du cluster.
#
#
if [ "${node}" = "master" ]
then
#  echange des clés ssh avec le LB
CopyIdLB
# 
#################################################
# 
# Configuration des noeuds pour acceder au proxy du loadbalancer
#
vrai="1"
environmentProxy && \
configWget && \
#profilproxy && \
dnfproxy && \
vrai="0"
nom="Etape ${numetape} - Configuration des noeuds pour acceder au proxy du loadbalancer"
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
# Installation du repo de Kubernetes
#
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
#
vrai="1"
containerd && \
vrai="0"
nom="Etape ${numetape} - Configuration et installation du service CONTAINERD , RUNC , CNI plugin"
#################################################
# 
# Démarrage du service kubelet
#
#
vrai="1"
mkdir -p /var/lib/kubelet/ && \
cat <<EOF > /var/lib/kubelet/config.yaml
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
EOF
systemctl daemon-reload && \
systemctl enable --now kubelet && \
vrai="0"
nom="Etape ${numetape} - Démarrage du service kubelet"
verif

#################################################
# 
# deployement du master
#
#
vrai="1"
if [ "$first" = "yes" ]
then
ssh root@loadBalancer-k8s.mon.dom 'sed -i -e "s|#    server noeud1|    server noeud1|g" /etc/haproxy/haproxy.cfg'
ssh root@loadBalancer-k8s.mon.dom systemctl restart haproxy.service
echo "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
echo "      Déploiement Kubernetes en cours "
echo "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
su -lc 'kubeadm init --control-plane-endpoint="`host loadBalancer-k8s.mon.dom | cut -f 4 -d " "`:6443" --upload-certs  --pod-network-cidr="192.168.0.0/19" &> /root/noeudsupplementaires.txt' && \
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
wget https://raw.githubusercontent.com/projectcalico/calico/v${VersionCalico}/manifests/tigera-operator.yaml && \
wget https://raw.githubusercontent.com/projectcalico/calico/v${VersionCalico}/manifests/custom-resources.yaml && \
sed -i "s|192.168.0.0/16|192.168.0.0/19|g" custom-resources.yaml && \
kubectl apply -f tigera-operator.yaml && \
kubectl apply -f custom-resources.yaml && \
vrai="0"
nom="Etape ${numetape} - Deploiement calico v${VersionCalico}"
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
##################################################
#
# choix du noeud maitre 2 ou 3
#
#
if [ "${noeud}${x}-k8s.mon.dom" = "master2-k8s.mon.dom" -o "${noeud}${x}-k8s.mon.dom" = "master3-k8s.mon.dom" ]
then 
#################################################
# 
# Echange de clés ssh avec master1-k8s.mon.dom
#
vrai="1"
CopyIdRoot && \
vrai="0"
nom="Etape ${numetape} - Echange des clés ssh avec master1-k8s.mon.dom"
verif
fi

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
if [ "${noeud}${x}-k8s.mon.dom" = "master2-k8s.mon.dom" ]
then 
ssh root@loadBalancer-k8s.mon.dom 'sed -i -e "s|#    server noeud2|    server noeud2|g" /etc/haproxy/haproxy.cfg'
ssh root@loadBalancer-k8s.mon.dom systemctl restart haproxy.service
elif [ "${noeud}${x}-k8s.mon.dom" = "master3-k8s.mon.dom" ]
then 
ssh root@loadBalancer-k8s.mon.dom 'sed -i -e "s|#    server noeud3|    server noeud3|g" /etc/haproxy/haproxy.cfg'
ssh root@loadBalancer-k8s.mon.dom systemctl restart haproxy.service
fi
echo "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
echo "      Déploiement d'un nouveau master en cours "
echo "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
source /root/.bashrc
kubeadm join 172.21.0.100:6443 --token ${token} --discovery-token-ca-cert-hash sha256:${tokensha} ${CertsKey}  && \
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
#################################################
# 
# Configuration des noeuds pour acceder au proxy du loadbalancer
#
vrai="1"
environmentProxy && \
configWget && \
#profilproxy && \
dnfproxy && \
vrai="0"
nom="Etape ${numetape} - Configuration des noeuds pour acceder au proxy du loadbalancer  OK"
verif
#################################################
#
# Echange des clés ssh avec master1-k8s.mon.dom
#
vrai="1"
ssh-keygen -b 4096 -t rsa -f ~/.ssh/id_rsa -P ""
CopyIdRoot
vrai="0"
nom="Etape ${numetape} - Echange des clés ssh avec master1-k8s.mon.dom"
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
# Installation du repo de Kubernetes
#
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
# installation de containerd
#
#
vrai="1"
containerd && \
vrai="0"
nom="Etape ${numetape} - Configuration et installation du service CONTAINERD , RUNC , CNI plugin"
#################################################
# 
# Démarrage du service kubelet
#
#
vrai="1"
mkdir -p /var/lib/kubelet/ && \
cat <<EOF > /var/lib/kubelet/config.yaml
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
EOF
systemctl daemon-reload && \
systemctl enable --now kubelet && \
vrai="0"
nom="Etape ${numetape} - Demarrage du service kubelet sur le worker"
verif
##############################################
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
echo "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
echo "      Déploiement d'un nouveau worker en cours "
echo "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
source /root/.bashrc
kubeadm join "172.21.0.100:6443" --token ${token}  --discovery-token-ca-cert-hash sha256:${tokencaworker} && \
vrai="0"
nom="Etape ${numetape} - Intégration du noeud worker au cluster"
verif
fi
