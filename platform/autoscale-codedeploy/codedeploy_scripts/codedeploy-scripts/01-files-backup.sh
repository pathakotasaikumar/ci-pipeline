#!/bin/bash

################################################################################################################################################

# This script will update the nginx configuration file when invoked throgh code deploy
#
################################################################################################################################################
source /root/context
BACKUPDIR="~/backup"
WEBDIR="/var/www/html/"
array=( index.html)

if [ ! -d "$BACKUPDIR" ]; then
  echo "The backup directory $BACKUPDIR doesn't exist, creating the directory"
  mkdir -p $BACKUPDIR
fi

echo "Backup of the current Apache files in progress"

for file in "${array[@]}"
do
    /bin/cp -f $WEBDIR/$file $BACKUPDIR/$file"_bkp"
    echo "Back up of configuration file $file"
done