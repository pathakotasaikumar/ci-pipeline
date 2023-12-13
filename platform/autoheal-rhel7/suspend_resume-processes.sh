#!/bin/bash
set -e

echo --------------------------------------------------
echo SuspendProcesses started `date`
echo --------------------------------------------------
echo

MTOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl --silent --max-time 3 -H "X-aws-ec2-metadata-token: $MTOKEN" http://169.254.169.254/latest/meta-data/instance-id)
ASG_NAME=$(/usr/local/bin/aws ec2 describe-tags --filters "Name=resource-id,Values=${INSTANCE_ID}" "Name=key,Values=aws:autoscaling:groupName" --query 'Tags[0].Value' --output text)

echo --------------------------------------------------
echo 1. SuspendProcesses - HealthCheck
echo --------------------------------------------------

/usr/local/bin/aws autoscaling suspend-processes \
--auto-scaling-group-name $ASG_NAME \
--scaling-processes HealthCheck

exit_code=$?

if [ $exit_code -eq 0 ]; then
	echo "Success - Suspended HealthCheck process on ASG ${ASG_NAME}"
else
	echo "Failed - Suspended HealthCheck process on ASG ${ASG_NAME}"
    exit $exit_code 
fi

echo --------------------------------------------------
echo 1. ResumeProcesses - HealthCheck
echo --------------------------------------------------

/usr/local/bin/aws autoscaling resume-processes \
--auto-scaling-group-name $ASG_NAME \
--scaling-processes HealthCheck

exit_code=$?

if [ $exit_code -eq 0 ]; then
	echo "Success - Resume HealthCheck process on ASG ${ASG_NAME}"
else
	echo "Failed - Resume HealthCheck process on ASG ${ASG_NAME}"
    exit $exit_code 
fi

exit $exit_code