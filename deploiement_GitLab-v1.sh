#!/bin/sh
dnf -y install curl policycoreutils openssh-server openssh-clients postfix
systemctl enable --now sshd
systemctl enable --now postfix
curl -s https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.rpm.sh | sudo bash
#dnf install -y gitlab-ce
#dnf install -y epel-release
#dnf install -y certbot
#certbot certonly --rsa-key-size 4096 --standalone --agree-tos --no-eff-email --email christophe@cmconsulting.online -d gitlab.mon.dom
#openssl dhparam -out /etc/gitlab/dhparams.pem 4096
#chmod 600 /etc/gitlab/dhparams.pem
sed -i 's|external_url 'http://gitlab.example.com'|external_url 'https://gitlab.mon.dom'|g' /etc/gitlab/gitlab.rb
#echo "nginx['redirect_http_to_https'] = true" >> /etc/gitlab/gitlab.rb
#echo "nginx['ssl_certificate'] = "/etc/letsencrypt/live/gitlab.mon.dom/fullchain.pem" " >> /etc/gitlab/gitlab.rb
#echo "nginx['ssl_certificate_key'] = "/etc/letsencrypt/live/gitlab.mon.dom/privkey.pem" " >> /etc/gitlab/gitlab.rb
#echo "nginx['ssl_dhparam'] = "/etc/gitlab/dhparams.pem" " >> /etc/gitlab/gitlab.rb
gitlab-ctl reconfigure
gitlab-ctl start
#curl -s https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.rpm.sh | sudo bash
firewall-cmd --add-service=ssh --permanent
firewall-cmd --add-service=http --permanent
firewall-cmd --add-service=https --permanent
firewall-cmd --reload

