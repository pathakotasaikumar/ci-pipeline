#!/bin/bash
#
# Detach an EBS volume from this instance
# Parameter volume-id Id of the EBS volume to attach to this instance
#
if [ $# -ne 1 ]; then
  (>&2 echo "Usage: detach_volume <volume-id>")
  exit 1
fi

VOLUME_ID=$1

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

$AWS ec2 detach-volume --region "$REGION" --volume-id "$VOLUME_ID"
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
  (>&2 echo "Volume $VOLUME_ID was detached successfully")
  exit 0
else
  (>&2 echo "ERROR: Error during detachment of volume $VOLUME_ID")
  exit $EXIT_CODE
fi
