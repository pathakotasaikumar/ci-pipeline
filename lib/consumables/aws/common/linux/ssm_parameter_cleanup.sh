#!/bin/bash

JQ_VERSION='1.5-1'

if [ $# -ne 1 ]; then
  (>&2 echo "Usage: ssm_parameter_cleanup <ssm parameterpath>")
  exit 1
fi

SSM_PARAMETER_INPUT_PATH=$1

# Determine the path to the aws cli tools
if [[ -f /usr/local/bin/aws ]]; then
  AWS=$(which aws) && echo "INFO: using aws binary ${AWS}"
elif [[ -f /usr/bin/aws ]]; then
  AWS=$(which aws) && echo "INFO: using aws binary ${AWS}"
else
  fail "Unable to locate AWS CLI tools. Cannot continue."
fi

# Input parameters
# 1: ssm parameter name
remove_ssm_parameter(){
  SSM_PARAMETER_NAME=$1
  $AWS ssm delete-parameter --name $SSM_PARAMETER_NAME
  [ $? -ne 0 ] && echo "Warning:- Failed to delete the ssm parameter $SSM_PARAMETER_NAME"
}

install_jq() {
  echo "INFO: Installing jq module"

  $AWS s3 cp s3://pipeline-artefact-store/jq-${JQ_VERSION}.x86_64.rpm /tmp/jq-${JQ_VERSION}.x86_64.rpm
  yum -y localinstall --nogpgcheck /tmp/jq-${JQ_VERSION}.x86_64.rpm
  [ $? -ne 0 ] && echo "Installation of jq is failed.Existing with no-zero code" && exit 1
}

[[ -z $(which jq) ]] && install_jq
JQ_BATH=$(which jq) && echo "INFO: Using jq binary path ${JQ_BATH}"

MTOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -s -m 2 -s -H "X-aws-ec2-metadata-token: $MTOKEN" http://169.254.169.254/latest/meta-data/instance-id)

SSM_PARAMETER_PATH="${SSM_PARAMETER_INPUT_PATH}/${INSTANCE_ID}"

SSM_PARAMETERS_OUTPUT=`$AWS ssm get-parameters-by-path --path $SSM_PARAMETER_PATH --with-decryption`

CHECK_PARAMETER_LENGTH=`$JQ_BATH '.Parameters | length' <(echo "$SSM_PARAMETERS_OUTPUT")`

if [[ "$CHECK_PARAMETER_LENGTH" -eq 0 ]]; then
   echo "No parameter exist for the $INSTANCE_ID"
else

   EXTRACTED_VALUE=`$JQ_BATH -r ['.Parameters[]| {ssmParamName: .Name}]' <(echo "$SSM_PARAMETERS_OUTPUT")`
   for (( i=0; i<"$CHECK_PARAMETER_LENGTH"; i++ )); do
     SSM_PARAMETER_NAME=`$JQ_BATH -r --arg j $i '.[$j | tonumber].ssmParamName' <(echo "$EXTRACTED_VALUE")`
     remove_ssm_parameter "$SSM_PARAMETER_NAME"
   done

fi

