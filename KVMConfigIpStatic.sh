#!/bin/bash
ConfHosts(){
cat <<EOF>> /etc/hosts
127.0.0.1   localhost.local localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost.local localhost localhost.localdomain localhost6 localhost6.localdomain6172.21.0.100 loadbalancer-k8s.mon.dom
172.21.0.101 master1-k8s.mon.dom
172.21.0.102 master2-k8s.mon.dom
172.21.0.103 master3-k8s.mon.dom
172.21.0.104 worker1-k8s.mon.dom
172.21.0.105 worker2-k8s.mon.dom
172.21.0.106 worker3-k8s.mon.dom
EOF
}
echo -n "Voulez vous exécuter le script initial de configuration IP ? [yes/no] : "
read rep
if [ "$rep" = "yes" -o "$rep" = "YES" -o "$rep" = "y" -o "$rep" = "Y" ]
then
clear
echo " Bienvenue dans le script d'installation IP du noeud"
echo "Choisir  - A - pour configurer l'adressage IP de  master1"
echo "Choisir  - B - pour configurer l'adressage IP de  master2"
echo "Choisir  - C - pour configurer l'adressage IP de  master3"
echo "Choisir  - 1 - pour configurer l'adressage IP de  worker1"
echo "Choisir  - 2 - pour configurer l'adressage IP de  worker2"
echo "Choisir  - 3 - pour configurer l'adressage IP de  worker3"
echo -n "Votre choix ? : "
read choix
case $choix in
    A)
        # configuration IP master1
        nmcli connection modify ens3 ipv4.addresses 172.21.0.101/24 ipv4.gateway 172.21.0.100 ipv4.dns 8.8.8.8 ipv4.method manual
	      nmcli connection up ens3
		    ConfHosts
        ;;
    B)
        # configuration IP master2
        nmcli connection modify ens3 ipv4.addresses 172.21.0.102/24 ipv4.gateway 172.21.0.100 ipv4.dns 8.8.8.8 ipv4.method manual
	      nmcli connection up ens3
	    	ConfHosts
        ;;
    C)
        # configuration IP master3
        nmcli connection modify ens3 ipv4.addresses 172.21.0.103/24 ipv4.gateway 172.21.0.100 ipv4.dns 8.8.8.8 ipv4.method manual
	      nmcli connection up ens3
		    ConfHosts
        ;;
    1)
        # configuration IP worker1
        nmcli connection modify ens3 ipv4.addresses 172.21.0.104/24 ipv4.gateway 172.21.0.100 ipv4.dns 8.8.8.8 ipv4.method manual
  	    nmcli connection up ens3
	    	ConfHosts
        ;;
    2)
        # configuration IP worker2
        nmcli connection modify ens3 ipv4.addresses 172.21.0.105/24 ipv4.gateway 172.21.0.100 ipv4.dns 8.8.8.8 ipv4.method manual
	      nmcli connection up ens3
	    	ConfHosts
        ;;
    3)
        # configuration IP worker3
        nmcli connection modify ens3 ipv4.addresses 172.21.0.106/24 ipv4.gateway 172.21.0.100 ipv4.dns 8.8.8.8 ipv4.method manual
	      nmcli connection up ens3
   	  	ConfHosts
        ;;
    *)
        # Relancer le script
        sh ./ConfIpStatic.sh
        ;;
esac
fi
echo -n "Voulez vous installer Kubernetes ? [yes/no] : "
read repKub
if [ "$repKub" = "yes" -o "$repKub" = "YES" -o "$repKub" = "y" -o "$repKub" = "Y" ]
then
	if [ -d ./Kubernetes ]
	then
	cd Kubernetes
	sh deploiement_multi_master-V-4.0.sh
	else
	git clone https://github.com/bloby01/Kubernetes
	cd Kubernetes
	sh deploiement_multi_master-V-4.0.sh
	fi
fi
