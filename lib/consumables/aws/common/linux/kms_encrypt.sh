#!/bin/bash

if [ $# -eq 2 ]
then
  KEY_ID="$1"
  PLAINTEXT="$2"
elif [ $# -eq 1 ]
then
  KEY_ID="$pipeline_KmsKeyArn"
  PLAINTEXT="$1"
else
  (>&2 echo "Usage: kms_encrypt [<key-id>] <plaintext string>")
  exit 1
fi

# Determine the path to the aws cli tools
if [[ -f /usr/local/bin/aws ]]; then
  AWS="/usr/local/bin/aws"
elif [[ -f /usr/bin/aws ]]; then
  AWS="/usr/bin/aws"
else
  fail "Unable to locate AWS CLI tools. Cannot continue."
fi

MTOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
REGION=`curl -s -m 3 -H "X-aws-ec2-metadata-token: $MTOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/.$//'`
[[ "${REGION}" = "" ]] && REGION='ap-southeast-2'

$AWS kms encrypt --region "${REGION}" --key-id "$KEY_ID" --plaintext "$PLAINTEXT" --output text --query CiphertextBlob
EXIT_CODE=$?

exit $EXIT_CODE