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
SOURCE_AWSCLI="<| AwsCliSource |>"
SOURCE_CFN="<| AwsCfnSource |>"
SECRET_MANAGEMENT_ARN="<| SecretManagementLambdaArn |>"
SSM_PLATFORM_PATH="<| SSMPlatformVariablePath |>"
SOURCE_CFN_PY="<| AwsCfnSourcepy |>"

# fallback to default values
SOURCE_AWSCLI=${SOURCE_AWSCLI:='https://awscli.amazonaws.com/awscli-exe-linux-x86_64-2.1.38.zip'}
SOURCE_CFN=${SOURCE_CFN:='https://s3.amazonaws.com/cloudformation-examples/aws-cfn-bootstrap-latest.zip'}
SOURCE_CFN_PY=${SOURCE_CFN_PY:='https://s3.amazonaws.com/cloudformation-examples/aws-cfn-bootstrap-py3-2.0-22.zip'}

# Set up the proxy
echo "INFO: setting proxy to ${AWS_PROXY}"
unset HTTP_PROXY;   [[ -n "$AWS_PROXY" ]] && export HTTP_PROXY="$AWS_PROXY"
unset HTTPS_PROXY;  [[ -n "$AWS_PROXY" ]] && export HTTPS_PROXY="$AWS_PROXY"
unset http_proxy;   [[ -n "$AWS_PROXY" ]] && export http_proxy="$AWS_PROXY"
unset https_proxy;  [[ -n "$AWS_PROXY" ]] && export https_proxy="$AWS_PROXY"
export no_proxy="$NO_PROXY"
export NO_PROXY="$NO_PROXY"

# Add additional entries to path to find tools
export PATH="${PATH}:/usr/local/bin:/opt/aws/aws-cfn-bootstrap/bin:/opt/aws/bin:/usr/local/aws:/usr/local/bin/aws"

# Clean out old logs
cat /dev/null > /var/log/cfn-init.log
cat /dev/null > /var/log/cfn-init-cmd.log
cat /dev/null > /var/log/cfn-wire.log
rm -rf /var/log/bootstrap.log
rm -rf /var/log/prospero*.log

MTOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(/usr/bin/curl -s -m 3 -H "X-aws-ec2-metadata-token: $MTOKEN" http://169.254.169.254/latest/meta-data/instance-id)
REMOTE_LOGS_PATH="<| RemoteLogsPath |>/$INSTANCE_ID"


function validate_exit_code()
{
    CODE=$1
    MGS=$2

    [ $CODE -eq 0 ] && echo "Exit code is 0, continue..."
    [ $CODE -ne 0 ] && echo "Exising with non-zero code [$CODE] - $MGS" && fail
}

function install_aws_cli {
  echo "INFO: Installing aws cli from [${SOURCE_AWSCLI}] using proxy ${AWS_PROXY}"
  curl -x ${AWS_PROXY} ${SOURCE_AWSCLI} -o 'awscliv2.zip'
  validate_exit_code $? "Unable to download ${SOURCE_AWSCLI} using proxy ${AWS_PROXY}"

  unzip awscliv2.zip
  validate_exit_code $? "Unable to unzip awscli V2"

  ./aws/install -i /usr/local/aws -b /usr/local/bin
  validate_exit_code $? "Unable to install awscli tools"

  chmod +x /usr/local/bin/aws && chmod +x /usr/local/bin && chmod 755 -R /usr/local/aws/
  rm -rf aws awscliv2.zip
}

function uninstall_aws_cli {
  echo "INFO: UnInstalling aws cli"
  rm -rf /usr/bin/aws /usr/local/bin/aws /usr/local/aws
  validate_exit_code $? "Unable to Uninstall"

  [[ -z $(which aws) ]] && install_aws_cli
  validate_exit_code $? "Unable to Install awscli V2"
}

function install_cfn_tools {
  echo "INFO: Installing aws-cfn-bootstrap from [${SOURCE_CFN}] using proxy [${AWS_PROXY}]"
  curl -x ${AWS_PROXY} --noproxy "" ${SOURCE_CFN} -o "aws-cfn-bootstrap-latest.zip"
  validate_exit_code $? "Unable to download ${SOURCE_CFN} using proxy ${AWS_PROXY}"

  unzip aws-cfn-bootstrap-latest.zip && pushd aws-cfn-bootstrap-1.4
  validate_exit_code $? "Unable to unzip aws-cfn-bootstrap"

  python setup.py install
  validate_exit_code $? "Unable to install ${SOURCE_CFN}"

  popd && rm -rf aws-cfn-bootstrap-1.4 aws-cfn-bootstrap-latest.zip
}

function install_cfn_tools_py {
  echo "INFO: Installing aws-cfn-bootstrap from [${SOURCE_CFN_PY}] using proxy [${AWS_PROXY}]"
  curl -x ${AWS_PROXY} --noproxy "" ${SOURCE_CFN_PY} -o "aws-cfn-bootstrap-latest.zip" 
  validate_exit_code $? "Unable to download ${SOURCE_CFN_PY} using proxy ${AWS_PROXY}"

  unzip aws-cfn-bootstrap-latest.zip && pushd aws-cfn-bootstrap-2.0
  validate_exit_code $? "Unable to unzip aws-cfn-bootstrap-py3-2.0-22"

  python setup.py install
  validate_exit_code $? "Unable to install ${SOURCE_CFN_PY}"

  popd && rm -rf aws-cfn-bootstrap-2.0 aws-cfn-bootstrap-latest.zip
}

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

function clean_vars {
  # Obfuscate variables in bamboo-vars file.
  remove_values=("ad_join" "bamboo_aem_admin_password" "customcookbooks" "snow" "sonar_bamboo" "api_gateway" "splunk" "qualys" "datadog")
  for value in ${remove_values[@]}; do
    sed -i "/${value}/d" /root/bamboo-vars.conf
  done
}

function process_secret(){
    echo "INFO: Executing lambda to process the platform secrects for Instance id $INSTANCE_ID"
    AWS_BIN=$1
    TMP_FILE=$(mktemp)
    PAYLOAD="{"EC2InstanceId": "$INSTANCE_ID","ExecutionType": "Instance"}"  
    #PYLD=$( jq -n --arg ins "$INSTANCE_ID"  --arg extp "Instance" '{ "EC2InstanceId" : $ins , "ExecutionType" : $extp }')
    #echo $PYLD| jq '.' | tee /tmp/pyld.json
    
        RESULT=`$AWS_BIN lambda invoke --invocation-type RequestResponse --function-name $SECRET_MANAGEMENT_ARN --payload '{"EC2InstanceId": "'"$INSTANCE_ID"'","ExecutionType": "Instance"}' --cli-binary-format raw-in-base64-out $TMP_FILE --query FunctionError`
        #RESULT=`$AWS_BIN lambda invoke --invocation-type RequestResponse --function-name $SECRET_MANAGEMENT_ARN --payload file:///tmp/pyld.json --cli-binary-format raw-in-base64-out $TMP_FILE --query FunctionError`
        [[ -n "$RESULT" && "$RESULT" != "null" ]] && cat $TMP_FILE  && fail "Failed to process platform secrets (exit_code="1")"
        [[ -z "$RESULT" || "$RESULT" == "null" ]] && echo "Successfully created the SSM parameters for Instance id $INSTANCE_ID"
      
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

# Install Zip utils if missing
if [ ! -z "$(cat /etc/redhat-release |grep -i -o 'Red Hat')" ] && [ ! -z "$(uname -a |grep -o 'el8')" ]
  then
    echo "Found RHEL8, installing python2 and setting it as an alternative"
    [[ -z $(which unzip) ]] && yum install zip unzip python2 python2-setuptools -y && alternatives --set python /usr/bin/python2
  else
    echo "Installing zip, unzip and python-setuptools"
    [[ -z $(which unzip) ]] && yum install zip unzip python-setuptools -y
fi

# Install aws cli if missing
[[ -z $(which aws) ]] && install_aws_cli || uninstall_aws_cli
AWS_BIN=$(which aws) && echo "INFO: using aws binary ${AWS_BIN}" && echo "INFO: using version: $( TMP_FILE=$(mktemp) && ${AWS_BIN} --version >> $TMP_FILE 2>&1  && cat $TMP_FILE)"

# Create SSM parameters
[[ -n "$SECRET_MANAGEMENT_ARN" ]] && process_secret $AWS_BIN

# Install cfn tools if missing
if [ ! -z "$(cat /etc/redhat-release |grep -i -o 'Red Hat')" ] && [ ! -z "$(uname -a |grep -o 'el9')" ]
  then
    [[ -z $(which cfn-init) ]] && install_cfn_tools_py
    CFN_PATH=$(dirname $(which cfn-init)) && echo "INFO: using path ${CFN_PATH}"
  else
    [[ -z $(which cfn-init) ]] && install_cfn_tools
    CFN_PATH=$(dirname $(which cfn-init)) && echo "INFO: using path ${CFN_PATH}"
    chmod +x $CFN_PATH/cfn-*
fi

# Execute cfn-init Prepare
echo "INFO: executing cfn-init Prepare step (region=$REGION; stack=$STACK_ID; resource=$METADATA_RESOURCE)"
${CFN_PATH}/cfn-init --region "${REGION}" --stack "${STACK_ID}" --resource "${METADATA_RESOURCE}" --configsets "Prepare"
EXIT_CODE=$?
[[ $EXIT_CODE -ne 0 ]] && fail "Failed to execute cfn-init Prepare step (exit_code=$EXIT_CODE)"

# Remove leftover files from SOE bake
rm -f /root/app.tar.gz /root/bamboo-vars.conf.bak /root/bootstrap.sh

[[ ! -f /root/context ]] && ln -s /etc/profile.d/context.sh /root/context && . /root/context

SSM_PARAMETER_CLEANUP=$(which ssm_parameter_cleanup) && echo "INFO: using ssm parameter cleanup path ${SSM_PARAMETER_CLEANUP}"

# Execute cfn-init Deploy
echo "INFO: executing cfn-init Deploy step (region=$REGION; stack=$STACK_ID; resource=$METADATA_RESOURCE)"
${CFN_PATH}/cfn-init --region "${REGION}" --stack "${STACK_ID}" --resource "${METADATA_RESOURCE}" --configsets "Deploy"
EXIT_CODE=$?
[[ $EXIT_CODE -ne 0 ]] && fail "Failed to execute cfn-init Deploy step (exit_code=$EXIT_CODE)"

# Copy the log from this script to /var/lib/cloud/instance/ for persistence across bakes
echo "INFO: copying cloud-init logs"
cat /var/log/cloud-init-output.log > /var/lib/cloud/instance/cloud-init-output.log

# Signal result of cfn-init back to CloudFormation
echo "INFO: signalling CloudFormation with cfn-signal (error=0; region=$REGION; stack=$STACK_ID; resource=$RESOURCE_TO_SIGNAL)"
clean_vars
upload_logs
$SSM_PARAMETER_CLEANUP $SSM_PLATFORM_PATH

# Signal result of cfn-init back to CloudFormation
echo "INFO: cfn-signal -e 0 --region ${REGION} --stack ${STACK_ID} --resource ${RESOURCE_TO_SIGNAL}"
${CFN_PATH}/cfn-signal -e 0 --region "${REGION}" --stack "${STACK_ID}" --resource "${RESOURCE_TO_SIGNAL}"

exit 0