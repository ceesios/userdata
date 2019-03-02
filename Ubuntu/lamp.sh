#!/bin/bash -v

# || true makes sure that the script continues with the next step if one fails.
# Update the cache and OS
apt update || true
DEBIAN_FRONTEND=noninteractive apt -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" dist-upgrade  || true

# Install packages
apt install apache2 mysql-server php libapache2-mod-php \
 php-mysql php-cli php-curl php-date php-xml php-gd php-json \
 php-mbstring openssl php-net-socket php-tokenizer php-imagick \
 php-gmagick

ufw allow in "Apache Full"