FROM centos:7
LABEL MAINTAINER christophe@cmconsulting.online
LABEL DESCRIPTION "Serveur web apache2 sur centos7 + php"
LABEL VERSION 3.1
RUN yum install -y httpd php \
 && ln -s /dev/stdout /var/log/httpd/access_log \
 && ln -s /dev/stderr /var/log/httpd/error_log
EXPOSE 80
COPY httpd-foreground /usr/sbin/httpd-foreground
ENTRYPOINT /usr/sbin/httpd-foreground
WORKDIR /var/www/html/
ADD index.php . 
