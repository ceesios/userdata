#!/bin/bash -v

# Installs nginx and set hostname in index.html for demo purposes.
apt-get update || true
apt-get install -y nginx || true
rm -vf /var/www/html/* || true
echo $(hostname) > /var/www/html/index.html || true
