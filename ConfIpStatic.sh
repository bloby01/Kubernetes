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
        
        ;;
    B)
        # configuration IP master2
        ;;
    C)
        # configuration IP master3
        ;;
    1)
        # configuration IP worker1
        ;;
    2)
        # configuration IP worker2
        ;;
    3)
        # configuration IP worker3
        ;;
    *)
        # Relancer le script
        sh ./ConfIpStatic.sh
        ;;
esac
