#!/bin/bash
echo "Bootstrapping"

#Install Webserver

echo "Installing HTTPD"
yum install httpd -y

if [ $? == 0 ]; then
  systemctl start httpd && systemctl enable httpd
  else
  exit 1
  fi
