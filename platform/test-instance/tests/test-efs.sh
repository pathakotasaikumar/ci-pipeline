#!/bin/bash
set -e

TIMESTAMP=`date`
REGION="ap-southeast-2"
ENDPOINT=$(dig $efs_FileSystemEndpoint @169.254.169.253 +short)

echo -n "Mounting file system $ENDPOINT..."
mkdir -p /mnt/efs
mount -t nfs -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2 ${ENDPOINT}:/ /mnt/efs
echo "Done"

echo -n "Testing write..."
FILE_CONTENTS="$TIMESTAMP write test"
echo "$FILE_CONTENTS" > /mnt/efs/testfile
echo "Done"

echo -n "Testing read..."
READ_OUTPUT=`cat /mnt/efs/testfile`
if [ "$READ_OUTPUT" != "$FILE_CONTENTS" ]; then
  echo "ERROR - file contents not what was written"
  exit 1
fi
echo "Done"

echo -n "Unmountiing file system"
FAILED=0
umount /mnt/efs || FAILED=1
if [ $FAILED -eq 1 ]; then
  echo "FAILED"
  echo -n "Forcing unmount"
  umount -f /mnt/efs
  echo "Done"
  exit 1
fi
echo "Done"

exit 0
