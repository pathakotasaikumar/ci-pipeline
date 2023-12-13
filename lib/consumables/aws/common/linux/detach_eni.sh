#!/bin/bash
#
# Detach eni from this instance
# Parameter eni-id Id of the nic to attach to this instance
# Parameter device mount point of the volume
#
if [ $# -ne 1 ]; then
  (>&2 echo "Usage: detach_eni eni-id")
  exit 1
fi

ENI_ID=$1

# Determine the path to the aws cli tools
if [[ -f /usr/local/bin/aws ]]; then
  AWS="/usr/local/bin/aws"
elif [[ -f /usr/bin/aws ]]; then
  AWS="/usr/bin/aws"
else
  fail "Unable to locate AWS CLI tools. Cannot continue."
fi

MTOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(/usr/bin/curl -s -m 3 -H "X-aws-ec2-metadata-token: $MTOKEN" http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl -s -m 3 -H "X-aws-ec2-metadata-token: $MTOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/.$//')

ENI_ATTACHMENT=$($AWS ec2 describe-network-interfaces --network-interface-ids $ENI_ID --region $REGION --query "NetworkInterfaces[0].Attachment.AttachmentId" --output text)

$AWS ec2 detach-network-interface --region "$REGION" --attachment-id "$ENI_ATTACHMENT"

EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
  echo "Network Interface '$ENI_ID' was detached successfully"
else
  echo "ERROR: Network Interface '$ENI_ID' was detached successfully"
  exit $EXIT_CODE
fi

