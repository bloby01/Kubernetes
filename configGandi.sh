#! /bin/sh


################################################################################
#                                                                              #
#                                                                              #
#                    Pré-configuration VMs Gandi                               #
#                                                                              #
#  1 ) Choix du poste à déployer (master ou worker)                            #
#  2 ) Installation de firewalld                                               #
#  3 ) Configuration du NAT                                                    #
#  4 ) Configuration des interfaces réseaux                                    #
#  5 ) Configuration des interfaces dans les zones appropriés                  #
#  6 ) Configuration du fichier /etc/sysconfig/gandi                           #
#  7 ) Configurer le client dns /etc/resolv.conf t du fichier /etc/hosts       #
#  8 ) Bloquer la fonction PostNetwork                                         #
#                                                                              #
################################################################################


# Version 1.1

################################################################################
#                                                                              #
#                    Déclaration variables                                     #
#                                                                              #
################################################################################
dns1="172.21.0.100"
dns2="8.8.8.8"
domain="mon.dom"
network="/etc/sysconfig/network"
eth="eth"
################################################################################
#                                                                              #
#                    Déclaration fonctions                                     #
#                                                                              #
################################################################################
config_motd_master() {
rm -f /etc/motd
cp MilleniumFalcon /etc/motd
}
config_motd_worker() {
rm -f /etc/motd
cp  pod /etc/motd
}
config_interface() {
cat <<EOF > /etc/sysconfig/network-scripts/ifcfg-${eth}${num}
DEVICE=${eth}${num}
ONBOOT=yes
NAME=${eth}${num}
IPADDR=${ip}
NETMASK=${netmask}
ZONE=${zone}
IPV6INIT=no
IPV6_AUTOCONF=no
EOF
}
config_interface0() {
cat <<EOF > /etc/sysconfig/network-scripts/ifcfg-eth0
DEVICE=eth0
ONBOOT=yes
NAME=eth0
IPADDR=
NETMASK=
ZONE=drop
IPV6INIT=no
IPV6_AUTOCONF=no
EOF
}

config_interface2() {
cat <<EOF > /etc/sysconfig/network-scripts/ifcfg-eth2
DEVICE=eth2
ONBOOT=yes
NAME=eth2
IPADDR=172.21.0.100
NETMASK=255.255.255.0
ZONE=trusted
IPV6INIT=no
IPV6_AUTOCONF=no
EOF
}
config_nat() {
firewall-cmd  --zone=trusted --add-masquerade --permanent
firewall-cmd  --zone=trusted --add-masquerade
}

config_gandi_master() {
sed -i -e "s|CONFIG_HOSTNAME=1|CONFIG_HOSTNAME=0|g" /etc/sysconfig/gandi
sed -i -e "s|CONFIG_NAMESERVER=1|CONFIG_NAMESERVER=0|g" /etc/sysconfig/gandi
sed -i -e "s|CONFIG_NODHCP=\"\"|CONFIG_NODHCP=\"eth0\ eth1\ eth2\"|g" /etc/sysconfig/gandi
sed -i -e "s|CONFIG_NETWORK=1|CONFIG_NETWORK=0|g" /etc/sysconfig/gandi
sed -i -e "s|CONFIG_MOTD=1|CONFIG_MOTD=0|g" /etc/sysconfig/gandi
}

config_gandi_worker() {
sed -i -e "s|CONFIG_HOSTNAME=1|CONFIG_HOSTNAME=0|g" /etc/sysconfig/gandi
sed -i -e "s|CONFIG_NAMESERVER=1|CONFIG_NAMESERVER=0|g" /etc/sysconfig/gandi
sed -i -e "s|CONFIG_NODHCP=\"\"|CONFIG_NODHCP=\"eth0\ eth1\"|g" /etc/sysconfig/gandi
sed -i -e "s|CONFIG_NETWORK=1|CONFIG_NETWORK=0|g" /etc/sysconfig/gandi
sed -i -e "s|CONFIG_MOTD=1|CONFIG_MOTD=0|g" /etc/sysconfig/gandi
echo "GATEWAY=172.21.0.100" >> ${network}
}

config_network() {
  if [ -f ${network} ]
  then
    echo "NETWORKING=yes" > ${network}
    echo "NETWORKING_IPV6=no" >> ${network}
    echo "IPV6_AUTOCONF=no" >> ${network}
    echo "DNS1=172.21.0.100" >> ${network}
    echo "DNS2=8.8.8.8" >> ${network}
    echo "DOMAIN=mon.dom" >> ${network}
  fi
}
config_hosts() {
cat <<EOF > /etc/hosts
127.0.0.1 localhost
EOF
}
config_postnetwork() {
cat <<EOF > /etc/sysconfig/network-scripts/ifup-post
#!/bin/bash
# Source the general functions for is_true() and is_false():
. /etc/init.d/functions
cd /etc/sysconfig/network-scripts
. ./network-functions
[ -f ../network ] && . ../network
unset REALDEVICE
if [ "$1" = --realdevice ] ; then
    REALDEVICE=$2
    shift 2
fi
CONFIG=$1
source_config
[ -z "$REALDEVICE" ] && REALDEVICE=$DEVICE
if is_false "$ISALIAS"; then
    /etc/sysconfig/network-scripts/ifup-aliases ${DEVICE} ${CONFIG}
fi
if ! is_true "$NOROUTESET"; then
    /etc/sysconfig/network-scripts/ifup-routes ${REALDEVICE} ${DEVNAME}
fi
# don't set hostname on ppp/slip connections
if [ "$2" = "boot" -a \
        "${DEVICE}" != lo -a \
        "${DEVICETYPE}" != "ppp" -a \
        "${DEVICETYPE}" != "slip" ]; then
    if need_hostname; then
        IPADDR=$(LANG=C ip -o -4 addr ls dev ${DEVICE} | awk '{ print $4 ; exit }')
        eval $(/bin/ipcalc --silent --hostname ${IPADDR} ; echo "status=$?")
        if [ "$status" = "0" ]; then
            set_hostname $HOSTNAME
        fi
    fi
fi
# Inform firewall which network zone (empty means default) this interface belongs to
if [ -x /usr/bin/firewall-cmd -a "${REALDEVICE}" != "lo" ]; then
    /usr/bin/firewall-cmd --zone="${ZONE}" --change-interface="${DEVICE}" > /dev/null 2>&1
fi
# Notify programs that have requested notification
do_netreport
if [ -x /sbin/ifup-local ]; then
    /sbin/ifup-local ${DEVICE}
fi
exit 0
EOF
}
config_iproute() {
cat <<EOF > /etc/sysconfig/network-scripts/route-${eth}${num}
0.0.0.0/0 via ${gateway} dev ${eth}${num}
EOF
}
config_resolvconf() {
cat <<EOF > /etc/resolv.conf
nameserver 172.21.0.100
nameserver 8.8.8.8
domain mon.dom
EOF
}

################################################################################
#                                                                              #
#                    Exécution code                                            #
#                                                                              #
################################################################################

#Choix du noeud master ou worker

clear
until [ "${noeud}" = "worker" -o "${noeud}" = "master" ]
do
echo -n 'Indiquez si cette machine doit être "master" ou "worker", mettre en toutes lettres votre réponse: '
read noeud
done


if [ "${noeud}" = "master" ]
then
# CONFIG MASTER install de firewalld et configuration du NAT et du réseau global + MOTD
yum install -y firewalld
systemctl enable --now firewalld
config_postnetwork
systemctl restart network
config_resolvconf
config_gandi_master
config_nat
config_network
config_motd_master
config_hosts
  for num in 1
  do
    clear
    echo "#######################################################"
    echo -n "Mettre l'adresse IP de l'interface ${eth}${num} :  "
    read ip
    echo "#######################################################"
    echo -n "Mettre l'adresse du MSR pour l'adresse ${ip} :  "
    read netmask
    if [ "${num}" = "1" ]
    then
    echo "#######################################################"
    echo -n "Mettre l'adresse de passerelle pour ${eth}${num} - ${ip} :  "
    read gateway
    echo "GATEWAY=${gateway}" >> ${network}
    echo "GATEWAY=${gateway}" >> ${network}-scripts/ifcfg-${eth}${num}
    echo "DNS1=${dns1}" >> ${network}-scripts/ifcfg-${eth}${num}
    echo "DNS2=${dns2}" >> ${network}-scripts/ifcfg-${eth}${num}
    echo "DOMAIN=${domain}" >> ${network}-scripts/ifcfg-${eth}${num}
    config_iproute
    fi
    echo "#######################################################"
    echo -n "Mettre la zone de firewall pour l'interface ${eth}${num} - ${ip} :  "
    read zone
    eth="eth"
    config_interface
  done
config_interface0
config_interface2
systemctl enable --now network
systemctl restart network
elif [ "${noeud}" = "worker" ]
then
# CONFIG WORKER install de firewalld et configuration du NAT et du réseau global + MOTD
yum install -y firewalld
systemctl enable --now firewalld
config_postnetwork
systemctl restart network
config_resolvconf
config_gandi_worker
config_network
config_motd_worker
  for num in 1
  do
    clear
    echo "#######################################################"
    echo -n "Mettre l'adresse IP de l'interface ${eth}${num} :  "
    read ip
    echo "#######################################################"
    echo -n "Mettre l'adresse du MSR pour l'adresse ${ip} :  "
    read netmask
    eth="eth"
    if [ "${num}" = "1" ]
    then
    echo "#######################################################"
    echo -n "Mettre l'adresse de passerelle pour ${eth}${num} - ${ip} :  "
    read gateway
    echo "GATEWAY=${gateway}" >> ${network}
    echo "GATEWAY=${gateway}" >> ${network}-scripts/ifcfg-${eth}${num}
    echo "DNS1=${dns1}" >> ${network}-scripts/ifcfg-${eth}${num}
    echo "DNS2=${dns2}" >> ${network}-scripts/ifcfg-${eth}${num}
    echo "DOMAIN=${domain}" >> ${network}-scripts/ifcfg-${eth}${num}
    config_iproute
    fi
    echo "#######################################################"
    echo -n "Mettre la zone de firewall pour l'interface ${eth}${num} - ${ip} :  "
    read zone
    config_interface
done
config_interface0
systemctl enable --now network
systemctl restart network
fi
