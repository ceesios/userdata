#!/bin/bash -v
#  
#  Author: Cees Moerkerken
#  https://github.com/ceesios/
#  https://virtu-on.nl
#
# This userdata script will
#   - install LAMP 
#   - install the required modules
#   - install fail2ban & configure ufw
#   - configure mysql with a WP database
#   - configure apache according to https://cipherli.st/ SSL Labs A+ rating
#   - deploy WordPress
#   - setup letsencrypt when the WP_DOMAIN resolves
#   
#
# Please provide your own variables below to customize your setup.
# All steps are logged in syslog for troubleshooting and most images will
# output the results to syslog, the console log and/or cloud-init-output.log.
#
# We will attempt to setup a lets-encrypt SSL certificate. This will only
# succeed when your domain already resolves to this instance. When this 
# userdata script is combined with terraform that includes cloudflare it will
# work.
# 
# Please mind that this script sets up a server that needs to be managed and 
# hardened. This is not something that is fully included in this script!
# Only fail2ban and UFW is setup in the most basic form. Generated passwords
# get logged insecurely.

function log () { logger -t userdata $1 ; }

log "Apt update, upgrade and install openssl"
apt update || true
DEBIAN_FRONTEND=noninteractive apt -y -o Dpkg::Options::="--force-confdef" \
 -o Dpkg::Options::="--force-confold" dist-upgrade  || true
apt install openssl -y || true
rm ~/.rnd || true


log "Setting variables"
WP_DOMAIN="wordpress.virtu-on.nl"
WP_ADMIN_USERNAME="admin"
WP_ADMIN_EMAIL="no@spam.org"
WP_PATH="/var/www/wordpress"
WP_DB_HOST="localhost"
WP_DB_NAME="wordpress"
WP_DB_USERNAME="wordpress"
WP_ADMIN_PASSWORD=$(openssl rand -base64 12)
MYSQL_ROOT_PASSWORD=$(openssl rand -base64 12)
WP_DB_PASSWORD=$(openssl rand -base64 12)

# outputs the generated passwords to the logs
echo "WP_ADMIN_PASSWORD = "$WP_ADMIN_PASSWORD
echo "MYSQL_ROOT_PASSWORD = "$MYSQL_ROOT_PASSWORD
echo "WP_DB_PASSWORD = "$WP_DB_PASSWORD
# outputs the WordPress user and password to the motd
echo "############################################################">>/etc/motd
echo "WP_ADMIN_USERNAME = "$WP_ADMIN_USERNAME >>/etc/motd
echo "WP_ADMIN_PASSWORD = "$WP_ADMIN_PASSWORD >>/etc/motd
echo "Remove this message from /etc/motd and change your password." >>/etc/motd
echo "############################################################">>/etc/motd


log "Set the initial mysql root password via debconf"
echo "mysql-server-5.7 mysql-server/root_password password\
 $MYSQL_ROOT_PASSWORD" | debconf-set-selections
echo "mysql-server-5.7 mysql-server/root_password_again password\
 $MYSQL_ROOT_PASSWORD" | debconf-set-selections
export DEBIAN_FRONTEND="noninteractive"


log "set hostname"
hostname $WP_DOMAIN

log "Install packages"
apt install -y apache2 mysql-server php libapache2-mod-php php-mysql php-json \
 php-cli php-curl php-date php-xml php-tokenizer php-mbstring php-net-socket \
 php-gd php-imagick php-gmagick fail2ban 


log "Configure ufw firewall"
ufw allow in "Apache Full"
ufw allow ssh
ufw deny out 25
ufw --force enable


log "Set .my.cnf"
tee ~/.my.cnf <<EOF
[client]
host     = localhost
user     = root
password = $MYSQL_ROOT_PASSWORD
socket   = /var/run/mysqld/mysqld.sock
EOF


log "Configure root_password on debian"
mysql -u debian-sys-maint -p$MYSQL_ROOT_PASSWORD -e \
"SET PASSWORD FOR 'root'@'localhost' = PASSWORD('$MYSQL_ROOT_PASSWORD');"||true


log "Create the WP database"
mysql -u root -p$MYSQL_ROOT_PASSWORD <<EOF
CREATE USER '$WP_DB_USERNAME'@'%' IDENTIFIED BY '$WP_DB_PASSWORD';
CREATE DATABASE $WP_DB_NAME;
GRANT ALL ON $WP_DB_NAME.* TO '$WP_DB_USERNAME'@'%';
EOF


log "waiting for WP database access"
until mysql -u $WP_DB_USERNAME -p$WP_DB_PASSWORD -h $WP_DB_HOST \
 -e "show databases"; do sleep 2; done
log "database found"


log "Create the WP directories"
mkdir -p $WP_PATH/public/
chown -R $USER $WP_PATH/public/


log "Disable the default apache config"
a2dissite *default


log "Create a new apache config for $WP_DOMAIN"
tee /etc/apache2/sites-available/100-$WP_DOMAIN.conf <<EOF
<VirtualHost *:80>
        ServerName $WP_DOMAIN
        ServerAlias www.$WP_DOMAIN

        ServerAdmin $WP_ADMIN_EMAIL
        DocumentRoot $WP_PATH/public

        LogFormat "%h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-agent}i\"" vhost_combined
        LogFormat "%v %h %l %u %t \"%r\" %>s %b" vhost_common

        ErrorLog \${APACHE_LOG_DIR}/$WP_DOMAIN.error.log
        CustomLog \${APACHE_LOG_DIR}/$WP_DOMAIN.access.log combined

        <Directory $WP_PATH/public/>
            AllowOverride All
        </Directory>

</VirtualHost>
EOF

tee /etc/apache2/sites-enabled/100-$WP_DOMAIN-le-ssl.conf <<EOF
SSLStaplingCache "shmcb:logs/stapling-cache(150000)"
<IfModule mod_ssl.c>
<VirtualHost *:443>
        ServerName $WP_DOMAIN
        ServerAlias www.$WP_DOMAIN

        ServerAdmin cees@$WP_DOMAIN
        DocumentRoot /var/www/wordpress/public

        ErrorLog \${APACHE_LOG_DIR}/$WP_DOMAIN.error.log
        CustomLog \${APACHE_LOG_DIR}/$WP_DOMAIN.access.log combined

        LogFormat "%h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-agent}i\"" vhost_combined
        LogFormat "%v %h %l %u %t \"%r\" %>s %b" vhost_common

        <Directory /var/www/wordpress/public/>
            AllowOverride All
        </Directory>

        SSLEngine on
        SSLProtocol All -SSLv2 -SSLv3 -TLSv1 -TLSv1.1
        SSLCipherSuite EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH
        SSLHonorCipherOrder on
        SSLCompression off
        SSLUseStapling on
        SSLSessionTickets Off
        SSLOptions +StrictRequire

        Header always set Strict-Transport-Security "max-age=63072000; includeSubDomains; preload"
        Header always set X-Frame-Options DENY
        Header always set X-Content-Type-Options nosniff

        SSLCertificateFile /etc/letsencrypt/live/$WP_DOMAIN/fullchain.pem
        SSLCertificateKeyFile /etc/letsencrypt/live/$WP_DOMAIN/privkey.pem
</VirtualHost>
</IfModule>
EOF

a2ensite 100-$WP_DOMAIN 100-$WP_DOMAIN-le-ssl
a2enmod rewrite headers
systemctl restart apache2


log "Downloading WP"
cd $WP_PATH/public/
wget https://wordpress.org/latest.tar.gz


log "Extracting WP"
tar xf latest.tar.gz --strip-components=1
tar --strip-components=1 -zxvf latest.tar.gz -C $WP_PATH/public
rm latest.tar.gz


log "Configuring WP"
mv wp-config-sample.php wp-config.php
sed -i s/database_name_here/$WP_DB_NAME/ wp-config.php
sed -i s/username_here/$WP_DB_USERNAME/ wp-config.php
sed -i s/password_here/$WP_DB_PASSWORD/ wp-config.php
sed -i s/localhost/$WP_DB_HOST/ wp-config.php
echo "define('FS_METHOD', 'direct');" >> wp-config.php
chown -R www-data:www-data $WP_PATH/public/


log "Call the WP install url"
curl -H "Host: $WP_DOMAIN" "http://127.0.0.1/wp-admin/install.php?step=2" \
  --data-urlencode "weblog_title=$WP_DOMAIN"\
  --data-urlencode "user_name=$WP_ADMIN_USERNAME" \
  --data-urlencode "admin_email=$WP_ADMIN_EMAIL" \
  --data-urlencode "admin_password=$WP_ADMIN_PASSWORD" \
  --data-urlencode "admin_password2=$WP_ADMIN_PASSWORD" \
  --data-urlencode "pw_weak=1"


log "Setting up letsencrypt"
add-apt-repository ppa:certbot/certbot -y
apt install -y python-certbot-apache

# try certbot (needs to resolve the domain to this instance)
certbot --apache -d $WP_DOMAIN -d www.$WP_DOMAIN -n --agree-tos --email \
 $WP_ADMIN_EMAIL || true
