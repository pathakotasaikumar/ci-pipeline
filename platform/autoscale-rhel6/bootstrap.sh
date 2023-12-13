#!/bin/bash
set -e
exec > >(tee /var/log/bootstrap.log | logger -t bootstrap -s 2>/dev/console) 2>&1
yum install httpd -y
if [ $? == 0 ]; then
  service httpd start && chkconfig httpd on
  else
  exit 1
  fi
echo "=> This is the autoheal bootstrap script for serverspec testing"

echo "Installing HTTPD"
yum install httpd -y

if [ $? == 0 ]; then
  service httpd start && chkconfig httpd on
else
  exit 1
fi

echo "Deploying html files"
tar -xvf html.tar.gz -C /var/www/html/

echo "Setting html file ownership to user 'apache'"
chown -R apache:apache /var/www/html

echo "Done"