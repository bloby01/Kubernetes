#!/bin/bash
clear
echo " Bienvenue dans le script d'installation IP du noeud"
echo -n "Choisir  - A - pour configurer l'adressage IP de  master1"
echo -n "Choisir  - B - pour configurer l'adressage IP de  master2"
echo -n "Choisir  - C - pour configurer l'adressage IP de  master3"
echo -n "Choisir  - 1 - pour configurer l'adressage IP de  worker1"
echo -n "Choisir  - 2 - pour configurer l'adressage IP de  worker2"
echo -n "Choisir  - 3 - pour configurer l'adressage IP de  worker3"
read choix
case $choix in
    A)
        # configuration IP master1
        ip a a dev enp0s3 172.21.0.101/24
        ip route add 0.0.0.0/0 via  172.21.0.100
        ;;
    B)
        # configuration IP master2
        ip a a dev enp0s3 172.21.0.102/24
        ip route add 0.0.0.0/0 via  172.21.0.100
        ;;
    C)
        # configuration IP master3
        ip a a dev enp0s3 172.21.0.103/24
        ip route add 0.0.0.0/0 via  172.21.0.100
        ;;
    1)
        # configuration IP worker1
        ip a a dev enp0s3 172.21.0.104/24
        ip route add 0.0.0.0/0 via  172.21.0.100
        ;;
    2)
        # configuration IP worker2
        ip a a dev enp0s3 172.21.0.105/24
        ip route add 0.0.0.0/0 via  172.21.0.100
        ;;
    3)
        # configuration IP worker3
        ip a a dev enp0s3 172.21.0.106/24
        ip route add 0.0.0.0/0 via  172.21.0.100
        ;;
    *)
        # Relancer le script
        sh ./ConfIpStatic.sh
        ;;
esac
