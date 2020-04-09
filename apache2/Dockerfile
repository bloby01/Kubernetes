FROM centos:7
LABEL MAINTAINER christophe@cmconsulting.online
LABEL DESCRIPTION "Serveur web apache2 sur centos7  avec quelques modules php"
LABEL VERSION 2.0
RUN yum install -y httpd \
 php-gd \
 php-json \
 php-dba \
 php-cli
RUN ln -sf /dev/stdout /var/log/httpd/access_log  &&  ln -sf /dev/stderr /var/log/httpd/error_log
EXPOSE 80 443
COPY httpd-foreground /usr/sbin/httpd-foreground
ENTRYPOINT /usr/sbin/httpd-foreground
