FROM rockylinux:9
LABEL MAINTAINER christophe.merle@gmail.com
LABEL DESCRIPTION "Serveur web apache2 sur RockyLinux + php"
LABEL VERSION 3.1
RUN dnf install -y httpd php
RUN ln -s /dev/stdout /var/log/httpd/access_log
RUN ln -s /dev/stderr /var/log/httpd/error_log
EXPOSE 80
COPY httpd-foreground /usr/sbin/httpd-foreground
RUN chmod +x /usr/sbin/httpd-foreground
ENTRYPOINT /usr/sbin/httpd-foreground
WORKDIR /var/www/html/
ADD index.php . 
