#!/bin/sh
dnf -y install curl policycoreutils openssh-server openssh-clients postfix
systemctl enable --now sshd
systemctl enable --now postfix
curl -s https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.rpm.sh | sudo bash
dnf install -y gitlab-ce
dnf install -y epel-release
dnf install -y certbot
certbot certonly --rsa-key-size 4096 --standalone --agree-tos --no-eff-email --email root@gitlab.mon.dom -d gitlab.mon.dom
openssl dhparam -out /etc/gitlab/dhparams.pem 4096
chmod 600 /etc/gitlab/dhparams.pem
cd /etc/gitlab/
   external_url 'https://gitlab.mon.dom'
