#!/bin/bash
set -e

echo "Install Packages"

yum install mysql nc -y

if [ $? == 0 ]; then
  echo "Installation of nc and mysql is successful."
  else
  exit 1
fi