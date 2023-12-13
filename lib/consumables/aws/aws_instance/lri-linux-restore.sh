#!/bin/bash
#
# This script is passed to a LRI EC2 Instances via userdata, and is executed via the standard cloud-init service
#

# Ensure environment is set up
. /etc/profile


# Write all output to /var/log/deploy.log
exec > >(tee /var/log/deploy.log | logger -t user-data -s 2>/dev/console) 2>&1

# Variables from the pipeline
RESOURCE_TO_SIGNAL="<| ResourceToSignal |>"
METADATA_RESOURCE="<| MetadataResource |>"
STACK_ID="<| StackId |>"
REGION="<| Region |>"
AWS_PROXY="<| AwsProxy |>"
NO_PROXY="<| NoProxy |>"
SOURCE_AWSCLI="<| AwsCliSource |>"
SOURCE_CFN="<| AwsCfnSource |>"
SOURCE_CFN_PY="<| AwsCfnSourcepy |>"
SECRET_MANAGEMENT_ARN="<| SecretManagementLambdaArn |>"
SSM_PLATFORM_PATH="<| SSMPlatformVariablePath |>"

CFN_PATH=$(dirname $(which cfn-init)) && echo "INFO: using path ${CFN_PATH}"

function fail {
  echo "ERROR: $1"
  # Signal result of cfn-init back to CloudFormation
  echo "INFO: signalling CloudFormation with cfn-signal (error=1; region=$REGION; stack=$STACK_ID; resource=$RESOURCE_TO_SIGNAL)"
  [ ! -z "$CFN_PATH" ] && $CFN_PATH/cfn-signal -e 1 --region "${REGION}" --stack "${STACK_ID}" --resource "${RESOURCE_TO_SIGNAL}"
  clean_vars
  upload_logs
  $SSM_PARAMETER_CLEANUP $SSM_PLATFORM_PATH
  exit 1
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
    /var/log/lri_bootstrap.log
  )

  for LOG_FILE in "${LOG_FILES[@]}"; do
    [[ -e $LOG_FILE ]] && ${AWS_BIN} s3 cp $LOG_FILE "s3://$REMOTE_LOGS_PATH/" --sse --acl bucket-owner-full-control --region "${REGION}" || echo "Upload of '$LOG_FILE' to S3 '$REMOTE_LOGS_PATH' has failed (exit code $?)"
  done
}


upload_logs

# Signal result of cfn-init back to CloudFormation
${CFN_PATH}/cfn-signal -e 0 --region "${REGION}" --stack "${STACK_ID}" --resource "${RESOURCE_TO_SIGNAL}"

exit 0