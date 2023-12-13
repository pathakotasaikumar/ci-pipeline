#!/bin/bash
set -e
exec > >(tee /var/log/bootstrap.log | logger -t bootstrap -s 2>/dev/console) 2>&1

echo "Installing Apache"
yum install httpd -y
chkconfig httpd on

echo "Deploying html files"
tar -xvf html.tar.gz -C /var/www/html/

echo "Setting html file ownership to user 'apache'"
chown -R apache:apache /var/www/html

echo "Done"