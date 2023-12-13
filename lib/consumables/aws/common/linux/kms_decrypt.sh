#!/bin/bash

if [ $# -ne 1 ]; then
  (>&2 echo "Usage: kms_decrypt <base64 ciphertext>")
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

# Decode base64-encoded ciphertext
CIPHERTEXT_FILE=`mktemp`
echo -e "$1" | base64 --decode > $CIPHERTEXT_FILE
if [ $? -ne 0 ]; then
  (>&2 echo "ERROR: ciphertext does not appear to be base64 encoded")
  exit 1
fi

MTOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
REGION=`curl -s -m 3 -H "X-aws-ec2-metadata-token: $MTOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/.$//'`
[[ "${REGION}" = "" ]] && REGION='ap-southeast-2'

$AWS kms decrypt --region "${REGION}" --ciphertext-blob "fileb://${CIPHERTEXT_FILE}" --output text --query Plaintext | base64 --decode
EXIT_CODE=$?
rm -f "${CIPHERTEXT_FILE}"

exit $EXIT_CODE
