#!/usr/bin/env bash
image_id="\"$image_ImageId\""
ami=`dig $image_DeployDnsName TXT +short`

if [ $ami == $image_id ]
  then
    echo "DNS derived record $ami matches image id: $image_id"
    exit 0
   else
    echo "No matching Ami found"
    exit 1
fi
