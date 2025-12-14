#!/bin/bash

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
        nmcli connection modify enp0s3 ipv4.addresses 172.21.0.101/24 ipv4.gateway 172.21.0.100 ipv4.dns 8.8.8.8 ipv4.method manual
	    nmcli connection up enp0s3
        ;;
    B)
        # configuration IP master2
        nmcli connection modify enp0s3 ipv4.addresses 172.21.0.102/24 ipv4.gateway 172.21.0.100 ipv4.dns 8.8.8.8 ipv4.method manual
	    nmcli connection up enp0s3
        ;;
    C)
        # configuration IP master3
        nmcli connection modify enp0s3 ipv4.addresses 172.21.0.103/24 ipv4.gateway 172.21.0.100 ipv4.dns 8.8.8.8 ipv4.method manual
	    nmcli connection up enp0s3
        ;;
    1)
        # configuration IP worker1
        nmcli connection modify enp0s3 ipv4.addresses 172.21.0.104/24 ipv4.gateway 172.21.0.100 ipv4.dns 8.8.8.8 ipv4.method manual
	    nmcli connection up enp0s3
        ;;
    2)
        # configuration IP worker2
        nmcli connection modify enp0s3 ipv4.addresses 172.21.0.105/24 ipv4.gateway 172.21.0.100 ipv4.dns 8.8.8.8 ipv4.method manual
	    nmcli connection up enp0s3
        ;;
    3)
        # configuration IP worker3
        nmcli connection modify enp0s3 ipv4.addresses 172.21.0.106/24 ipv4.gateway 172.21.0.100 ipv4.dns 8.8.8.8 ipv4.method manual
	    nmcli connection up enp0s3
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
