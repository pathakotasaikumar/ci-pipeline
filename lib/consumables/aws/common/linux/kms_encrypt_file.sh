#!/bin/bash
#
# kms_encrypt_file
# -----------------
# This script is used to assist in the encryption of files with the AWS KMS service.
# Please be aware that You can encrypt up to 4 kilobytes (4096 bytes) of arbitrary data such as
# an RSA key, a database password, or other sensitive information.
# For decryption, please see the corrosponding helper kms_decrypt_file.
# 
# Usage:
# -------
# When executed, pass the script the file to be encrypted as well as the filename you wish
# to have the encrypted output written to.
# By default, the script will use KMS ARN ID for your QCP Application ID as sourced from the 
# deployments context file. If you need to specify an alternate key ARN, please do so as $1
# 
# Example:
# - Using the application context ARN
#   $ kms_encrypt_file /etc/hosts /tmp/hosts.kms
#
# - Using an alternate ARN for encryption
#   $ kms_encrypt_file aws:kms:ap-southeast-2:695837244598:key/919a04a9-e248-4ad6-aaaa-4fb110de4109 \
#     /etc/hosts /tmp/hosts.kms
#
#

case $# in 

  '2' ) 
      KEY_ID="$pipeline_KmsKeyArn"
      INPUT_FILE="$1"
      OUTPUT_FILE="$2"
  ;;

  '3' )
      KEY_ID="$1"
      INPUT_FILE="$2"
      OUTPUT_FILE="$3"
  ;;

  * ) 
      echo "Usage: kms_encrypt_file [<key id>] <input file> <output file>"
      exit 1
  ;;

esac 

# Determine the path to the aws cli tools
if [[ -f /usr/local/bin/aws ]]; then
  AWS="/usr/local/bin/aws"
elif [[ -f /usr/bin/aws ]]; then
  AWS="/usr/bin/aws"
else
  echo  "Unable to locate AWS CLI tools. Cannot continue."
  exit 1
fi

if [ ! -f ${INPUT_FILE} ]; then
  echo "The file ${INPUT_FILE} does not exist. Cannot continue"
  exit 1
fi

MTOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
REGION=`curl -s -m 3 -H "X-aws-ec2-metadata-token: $MTOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/.$//'`
[[ "${REGION}" = "" ]] && REGION='ap-southeast-2'

$AWS kms encrypt --region "$REGION" --key-id "$KEY_ID" --plaintext "fileb://${INPUT_FILE}" --output text --query CiphertextBlob > "${OUTPUT_FILE}"
EXIT_CODE=$?

exit $EXIT_CODE