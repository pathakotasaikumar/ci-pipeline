#!/bin/bash
#
# kms_decrypt_file
# -----------------
# This script is used to assist in the decryption of files with the AWS KMS service.
# For encryption, please see the corrosponding helper kms_decrypt_file.
# 
# Usage:
# -------
# When executed, pass the script the file to be decrypted as well as the filename you wish
# to have the decrypted output written to.
# 
# Example:
# kms_decrypt_file /tmp/hosts.ks /tmp/decrypt.out
#

if [ $# -ne 2 ]; then
  (>&2 echo "Usage: kms_decrypt_file <INPUT_FILE> <OUTPUT_FILE>")
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

INPUT_FILE="$1"
OUTPUT_FILE="$2"

# Checking the file is base64 encoded
TEMP_FILE=`mktemp`
base64 -d "${INPUT_FILE}" > ${TEMP_FILE}
if [ $? -ne 0 ]; then
    echo "ERROR: Input file does not appear to be base64 encoded. Cannot continue"
    rm -f ${TEMP_FILE}
  exit 1
fi

MTOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
REGION=`curl -s -m 3 -H "X-aws-ec2-metadata-token: $MTOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/.$//'`
[[ "${REGION}" = "" ]] && REGION='ap-southeast-2'

$AWS kms decrypt --region "${REGION}" --ciphertext-blob "fileb://${TEMP_FILE}" --output text --query Plaintext | base64 --decode > "${OUTPUT_FILE}"
EXIT_CODE=$?
rm -f "${TEMP_FILE}"

exit $EXIT_CODE