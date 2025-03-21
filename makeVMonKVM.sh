#!/bin/sh
#########################################################################
#									#
# Outil de construction de VMs dans un environnement Linux KVM By	#
#			ste.cmc.merle@gmail.com				#
#									#
# - Vérification de la présence des outils et installation		#
# - Création d'un network sans dhcp					#
# - Création de disque							#
# - Téléchargement ISO RockyLinux					#					
# - Création de VM et boot sur ISO					#
#########################################################################
#
#	Configuration des app de virtualisation sur le system hôte
#
systemHote(){
dnf install -y qemu-kvm libvirt virt-install bridge-utils dnsmasq && \
systemctl enable --now libvirtd
cat <<EOF | tee network-k8s.xml
<network>
  <name>nat-k8s</name>
  <forward mode="nat"/>
  <bridge name="toto" stp="on" delay="0"/>
  <ip address="172.21.0.1" netmask="255.255.255.0">
  </ip>
</network>
EOF
virsh net-define --file network-k8s.xml
systemctl restart libvirtd
virsh net-start nat-k8s
virsh net-autostart nat-k8s
}
#
#################################################
#
#	Creation des disques pour les VMs
#
createDiskVms(){
echo -n "quelle doit être la taille du disque principal de la VM [ex: 20] ? : "
read tailleDisquePrincipal
qemu-img create -f qcow2 ${noeud}${x}.qcow2 ${tailleDisquePrincipal}G
}
#
#################################################
#
#	Download de l'iso
#
download(){
if [ -f /home/user/rocky.iso ]
then
echo "le fichier iso de rocky est disponible : $(ls -lh /home/user/rocky.iso)"
sleep 4
else
wget -O /home/user/rocky.iso https://dl.rockylinux.org/pub/rocky/9/isos/x86_64/Rocky-9-latest-x86_64-boot.iso
fi
}
#
#################################################
#
#	Construction des VMs
#
constructionVM(){
isoRocky="/home/user/rocky.iso"
virt-install --name VM-${noeud}${x}.qcow2 --ram 3072 --vcpus 2 --disk path=${noeud}${x}.qcow2,format=qcow2 --cdrom ${isoRocky} --boot cdrom --os-variant rocky9 --network network=nat-k8s,model=virtio --graphics vnc --virt-type qemu --hvm
}
#################################################
# 
#Fonction de vérification des étapes
#

verif(){
	numetape=`expr ${numetape} + 1 `
	  if [ "${vrai}" -eq "0" ]; then
	    echo "Machine: ${node}${x}-k8s.mon.dom - ${nom} - OK"
	  else
	    echo "Erreur sur Machine: ${node}${x}-k8s.mon.dom - ${nom} - OUPSSS "
	    exit 0
	  fi
}
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
