#!/bin/sh

# Démarrage de PHP-FPM en arrière-plan
php-fpm83

# Démarrage de Nginx au premier plan
nginx -g "daemon off;"
