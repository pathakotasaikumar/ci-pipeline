#!/usr/bin/env bash

if [ $# -ne 2 ]; then
  (>&2 echo "Usage: mount.sh <device> <mount>")
  exit 1
fi

DEV=$1
MOUNT=$2
unset TYPE

if [ ! -b $DEV ]; then
  echo "Device $DEV not found" && exit 1
fi


# check FS used for the volume argument and assign to TYPE variable with eval
BLOCKDEV=`blkid $DEV | awk ' { print $3 } '`

if [[ $BLOCKDEV =~ "TYPE" ]]; then
  echo "Filesystem is already present"
else
  echo "Formatting filesystem on $DEV as ext4"
  /sbin/mkfs.ext4 $DEV
fi

if [ ! -d $MOUNT ]
  then
    mkdir -m 751 $MOUNT
fi

if !(grep -Fxq "$DEV $MOUNT auto noatime 0 0" /etc/fstab)
  then
    echo "$DEV $MOUNT auto noatime 0 0" | tee -a /etc/fstab
  else
    echo "Device mount already found in /etc/fstab"
fi

if mount | grep $MOUNT > /dev/null; then
    echo "$MOUNT is already mounted"
else
    echo "Mounting $MOUNT"
    mount $MOUNT
fi

timestamp=`date +%s`
touch $MOUNT/$timestamp
rm $MOUNT/$timestamp