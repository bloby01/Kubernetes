#!/bin/sh

###################################################################################################
#                                                                                                 #
#                             Debut de la séquence d'Installation                                 #
#                                                                                                 #
###################################################################################################
#
#				Pre-requis systeme hôte
#
systemHote


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
#                       Création des disques durs                                          #
#                                                                                          #
############################################################################################
clear
# Création du disque dur 
createDiskVms
# Téléchargement de l'iso
download
# Construction de la VM et boot sur iso pour installation
constructionVM
