#!/usr/bin/env bash
# Bootstrap script for simple sinatra/unicorn demo application
# Install required prerequisites

source /etc/profile
source /root/context

yum install -y amazon-linux-extras
amazon-linux-extras install ruby2.6
yum install ruby-devel gcc -y
alternatives --set ruby /usr/bin/ruby2.6

gem sources --add http://nexus.qcpaws.qantas.com.au/nexus/repository/gems-all/
gem sources --remove https://rubygems.org/
gem sources -c
gem install sinatra --no-document
gem install unicorn --no-document

# Configure Application root directory
APP_ROOT='/app'
mkdir -p $APP_ROOT/tmp/sockets
mkdir -p $APP_ROOT/tmp/pids
mkdir -p $APP_ROOT/log
mkdir -p $APP_ROOT/tmp/pids

# Copy all application files to App root
cp -R app/* $APP_ROOT/

# Set permissions
chown nobody:nobody $APP_ROOT -R
chmod 750 $(find $APP_ROOT -type d)
chmod 640 $(find $APP_ROOT -type f)

# Configure unicorn startup script
chmod +x $APP_ROOT/sbin/unicorn
ln -s $APP_ROOT/sbin/unicorn /etc/init.d/unicorn

# Enable unicorn service
chkconfig unicorn on
service unicorn start