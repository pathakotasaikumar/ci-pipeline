#!/bin/bash
#
# Attach an EBS volume to this instance
# Parameter volume-id Id of the EBS volume to attach to this instance
# Parameter device mount point of the volume
#
if [ $# -ne 2 ]; then
  (>&2 echo "Usage: attach_volume volume-id device")
  exit 1
fi

VOLUME_ID=$1
DEVICE=$2

# Determine the path to the aws cli tools
if [[ -f /usr/local/bin/aws ]]; then
  AWS="/usr/local/bin/aws"
elif [[ -f /usr/bin/aws ]]; then
  AWS="/usr/bin/aws"
else
  fail "Unable to locate AWS CLI tools. Cannot continue."
fi

MTOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
REGION=$(curl -s -m 3 -H "X-aws-ec2-metadata-token: $MTOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/.$//')
INSTANCE_ID=$(/usr/bin/curl -s -m 3 -H "X-aws-ec2-metadata-token: $MTOKEN" http://169.254.169.254/latest/meta-data/instance-id)

$AWS ec2 attach-volume --region "$REGION" --volume-id "$VOLUME_ID" --instance-id "$INSTANCE_ID" --device "$DEVICE"
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
  (>&2 echo "Volume $VOLUME_ID was attached successfully")
  exit 0
else
  (>&2 echo "ERROR: Error during attachment of volume $VOLUME_ID")
  exit $EXIT_CODE
fi