#!/bin/bash
#
# This script is passed to an EC2 Instances via its userdata, and is executed via the standard cloud-init service
#
# The output logs of this script are located at:
#    /var/log/deploy.log
#    /var/log/cloud-init-output.log
#    /var/lib/cloud/instance/cloud-init-output.log
#    /dev/console
# Note: /var/lib/cloud/instance is a symlink to /var/lib/cloud/instances/<current instance-id>
#

# Write all output to /var/log/deploy.log
exec > >(tee /var/log/deploy.log | logger -t user-data -s 2>/dev/console) 2>&1

# Ensure environment is set up
. /etc/profile

# Variables from the pipeline
RESOURCE_TO_SIGNAL="<| ResourceToSignal |>"
METADATA_RESOURCE="<| MetadataResource |>"
STACK_ID="<| StackId |>"
REGION="<| Region |>"
AWS_PROXY="<| AwsProxy |>"
NO_PROXY="<| NoProxy |>"
SSM_PLATFORM_PATH="<| SSMPlatformVariablePath |>"

# Set up the proxy
echo "INFO: setting proxy to ${AWS_PROXY}"
unset HTTP_PROXY;   [[ -n "$AWS_PROXY" ]] && export HTTP_PROXY="$AWS_PROXY"
unset HTTPS_PROXY;  [[ -n "$AWS_PROXY" ]] && export HTTPS_PROXY="$AWS_PROXY"
unset http_proxy;   [[ -n "$AWS_PROXY" ]] && export http_proxy="$AWS_PROXY"
unset https_proxy;  [[ -n "$AWS_PROXY" ]] && export https_proxy="$AWS_PROXY"
export no_proxy="$NO_PROXY"
export NO_PROXY="$NO_PROXY"

# Add additional entries to path to find tools
export PATH="${PATH}:/usr/local/bin:/opt/aws/aws-cfn-bootstrap/bin:/opt/aws/bin:/usr/local/aws"

MTOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(/usr/bin/curl -s -m 3 -H "X-aws-ec2-metadata-token: $MTOKEN"  http://169.254.169.254/latest/meta-data/instance-id)

echo "INFO: cfn-get-metadata --region ${REGION} --stack ${STACK_ID} --resource ${RESOURCE_TO_SIGNAL} --key WAIT_CONDITION"
WAIT_CONDITION_RESOURCE=$(cfn-get-metadata --region ${REGION} --stack ${STACK_ID} --resource ${RESOURCE_TO_SIGNAL} --key WAIT_CONDITION)
REMOTE_LOGS_PATH="<| RemoteLogsPath |>/${WAIT_CONDITION_RESOURCE}/${INSTANCE_ID}"
SSM_PARAMETER_CLEANUP=$(which ssm_parameter_cleanup) && echo "INFO: using ssm parameter cleanup path ${SSM_PARAMETER_CLEANUP}"

function fail {
  echo "ERROR: $1"
  # Signal result of cfn-init back to CloudFormation
  echo "INFO: signalling CloudFormation with cfn-signal (error=1; region=$REGION; stack=$STACK_ID; resource=$WAIT_CONDITION_RESOURCE)"
  cfn-signal -e 1 --region "${REGION}" --stack "${STACK_ID}" --resource "${WAIT_CONDITION_RESOURCE}"
  clean_vars
  upload_logs
  $SSM_PARAMETER_CLEANUP $SSM_PLATFORM_PATH
  exit 1
}

function clean_vars {
  # Obfuscate variables in bamboo-vars file.
  remove_values=("ad_join" "bamboo_aem_admin_password" "customcookbooks" "snow" "sonar_bamboo" "api_gateway" "splunk" "qualys" "datadog")
  for value in ${remove_values[@]}; do
    sed -i "/${value}/d" /root/bamboo-vars.conf
  done
}

function upload_logs {
  LOG_FILES=(
    /var/log/cfn-init.log
    /var/log/cfn-init-cmd.log
    /var/log/cfn-wire.log
    /var/log/deploy.log
    /var/log/messages
    /var/log/prospero*.log
    /root/context
  )

  for LOG_FILE in "${LOG_FILES[@]}"; do
    [[ -e $LOG_FILE ]] && aws s3 cp $LOG_FILE "s3://$REMOTE_LOGS_PATH/" --sse --acl bucket-owner-full-control --region "${REGION}" || echo "Upload of '$LOG_FILE' to S3 '$REMOTE_LOGS_PATH' has failed (exit code $?)"
  done
}

# Execute cfn-init Prepare
echo "INFO: executing cfn-init Prepare step (region=$REGION; stack=$STACK_ID; resource=$METADATA_RESOURCE)"
cfn-init --region "${REGION}" --stack "${STACK_ID}" --resource "${METADATA_RESOURCE}" --configsets "Prepare"
EXIT_CODE=$?
[[ $EXIT_CODE -ne 0 ]] && fail "Failed to execute cfn-init Prepare step (exit_code=$EXIT_CODE)"

# Remove leftover files from SOE bake
rm -f /root/app.tar.gz /root/bamboo-vars.conf.bak /root/bootstrap.sh

[[ ! -f /root/context ]] && ln -s /etc/profile.d/context.sh /root/context && . /root/context

# Execute cfn-init Deploy
echo "INFO: executing cfn-init Deploy step (region=$REGION; stack=$STACK_ID; resource=$METADATA_RESOURCE)"
cfn-init --region "${REGION}" --stack "${STACK_ID}" --resource "${METADATA_RESOURCE}" --configsets "Deploy"
EXIT_CODE=$?
[[ $EXIT_CODE -ne 0 ]] && fail "Failed to execute cfn-init Deploy step (exit_code=$EXIT_CODE)"

# Copy the log from this script to /var/lib/cloud/instance/ for persistence across bakes
echo "INFO: copying cloud-init logs"
cat /var/log/cloud-init-output.log > /var/lib/cloud/instance/cloud-init-output.log
clean_vars
upload_logs
$SSM_PARAMETER_CLEANUP $SSM_PLATFORM_PATH

# Signal result of cfn-init back to CloudFormation
echo "INFO: signalling CloudFormation with cfn-signal (error=0; region=$REGION; stack=$STACK_ID; resource=$WAIT_CONDITION_RESOURCE)"
cfn-signal -e 0 --region "${REGION}" --stack "${STACK_ID}" --resource "${WAIT_CONDITION_RESOURCE}"

exit 0
