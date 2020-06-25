1

#!/bin/sh

2

#   Version : 0.2.4

3

#   !!!!!!!!!!!!!  pas fini !!!!!!!!!!!!!!!!!!!!

4

#   !!!!!!!!!!!!!   vérifier le proxy avec login et password

5

#

6

# Script de déploiment kubernetes

7

# By christophe@cmconsulting.online

8

#

9

# Script destiné à faciliter le déploiement de cluster kubernetes

10

# Il est à exécuter dans le cadre d'une formation.

11

# Il ne doit pas être exploité pour un déploiement en production.

12

#

13

#

14

#

15

#################################################################################

16

#                                                                               #

17

#                       LABS  Kubernetes                                        #

18

#                                                                               #

19

#                                                                               #

20

#               Internet                                                        #

21

#                   |                                                           #

22

#                  master1 (VM) DHCPD NAMED NAT                                 #

23

#                       |                                                       #

24

#                      -------------------                                      #

25

#                      |  switch  interne|--(VM) Client linux                   #

26

#                      |-----------------|                                      #

27

#                        |     |      |                                         #

28

#                        |     |      |                                         #

29

#                 (vm)worker1  |      |                                         #

30

#                      (vm)worker2    |                                         #

31

#                            (vm) worker3                                       #

32

#                                                                               #

33

#                                                                               #

34

#                                                                               #

35

#################################################################################

36

#                                                                               #

37

#                          Features                                             #

38

#                                                                               #

39

#################################################################################

40

#                                                                               #

41

# - Le système sur lequel s'exécute ce script doit être un CentOS7              #

42

# - Le compte root doit etre utilisé pour exécuter ce Script                    #

43

# - Le script requière que la machine master soit correctement configuré sur IP #

44

#   master-k8s.mon.dom carte interne enp0s8 -> 172.21.0.100/24 (pré-configurée) #

45

#   master-k8s.mon.dom carte externe enp0s3 -> XXX.XXX.XXX.XXX/YY               #

46

# - Le réseau sous-jacent du cluster est basé Calico                            #
