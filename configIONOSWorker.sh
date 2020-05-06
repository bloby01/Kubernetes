#! /bin/sh


################################################################################
#                                                                              #
#                                                                              #
#                    Pré-configuration VMs worker sur cloud IONOS              #
#                                                                              #
#  1 ) Configuration du clavier en français  azerty                            #
#  2 ) Configuration des interfaces réseaux                                    #
#  3 ) Configuration des interfaces dans les zones appropriés                  #
#  4 ) Configurer le fichier /etc/hosts                                        #
#  5 ) restart le service réseau                                               #
#  6 ) configuration motd                                                      #
#  5 ) configuration sshd                                                      #
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
eth="ens"
################################################################################
#                                                                              #
#                    Déclaration fonctions                                     #
#                                                                              #
################################################################################
config_clavier_fr() {
  loadkeys fr
}

config_sshd() {
  sed -i -e  "s|#PermitRootLogin yes|PermitRootLogin yes|g" /etc/ssh/sshd_config
  sed -i -e  "s|PermitRootLogin without-password|#PermitRootLogin without-password|g" /etc/ssh/sshd_config
  sed -i -e  "s|PasswordAuthentication no|PasswordAuthentication yes|g" /etc/ssh/sshd_config
}

config_motd_worker() {
rm -f /etc/motd
cp pod /etc/motd
}

config_interface0() {
cat <<EOF > /etc/sysconfig/network-scripts/ifcfg-ens6
DEVICE=ens6
ONBOOT=yes
NAME=ens6
BOOTPROTO=dhcp
ZONE=trusted
IPV6INIT=no
IPV6_AUTOCONF=no
EOF
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

################################################################################
#                                                                              #
#                    Exécution code                                            #
#                                                                              #
################################################################################

config_motd_worker
config_interface0
config_network
config_hosts
config_clavier_fr
config_sshd
systemctl restart sshd
systemctl restart NetworkManager
