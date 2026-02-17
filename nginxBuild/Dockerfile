FROM alpine:latest

# Installation de Nginx et PHP-FPM
RUN apk add --no-cache \
    nginx \
    php83 \
    php83-fpm \
#    && ln -s /usr/bin/php83 /usr/bin/php \
    && mkdir -p /run/nginx \
    && mkdir -p /var/www/html

# Configuration Nginx
COPY nginx.conf /etc/nginx/nginx.conf
COPY default.conf /etc/nginx/http.d/default.conf

# mappage de fichier de logs
RUN ln -s /dev/sdtout /var/log/nginx/access.log
RUN ln -s /dev/stderr /var/log/nginx/error.log

# Configuration PHP-FPM pour écouter sur un socket
RUN sed -i 's/listen = 127.0.0.1:9000/listen = \/run\/php-fpm.sock/' /etc/php83/php-fpm.d/www.conf \
    && sed -i 's/;listen.owner = nobody/listen.owner = nginx/' /etc/php83/php-fpm.d/www.conf \
    && sed -i 's/;listen.group = nobody/listen.group = nginx/' /etc/php83/php-fpm.d/www.conf \
    && sed -i 's/user = nobody/user = nginx/' /etc/php83/php-fpm.d/www.conf \
    && sed -i 's/group = nobody/group = nginx/' /etc/php83/php-fpm.d/www.conf

# Copie de l'application
COPY index.php /var/www/html/index.php

# Permissions
RUN chown -R nginx:nginx /var/www/html

# Script de démarrage
COPY start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 80

CMD ["/start.sh"]
