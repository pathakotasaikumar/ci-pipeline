#!/bin/bash
# S3 Versioning management helper script.
# Keiran Sweet <keiran.sweet@sourcedgroup.com>
# This script will help you enable and suspend versioning on your S3 buckets
# within the QCP environment quickly from your EC2 instances.
# This requires the AWS CLI to function & suitable S3 permissions from IAM
#
# Usage:
# configure_s3_versioning.sh { enable | suspend | status } [ bucketname ]
# Usage is straightforward. If bucketname is ommited, it will be set to the value of the
# pipeline_AppBucketName from your context file.
#
# Note: If status returns no output, it means the bucket has not had versioning enabled.

MTOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
REGION=$(curl -s -m 3 -H "X-aws-ec2-metadata-token: $MTOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/.$//')

case $# in

  '0')
     echo "Enable/Suspend versioning on your assigned application bucket or other bucket you have access to manage"
     echo "Usage: $0 { enable | suspend | status } [ bucketname ]"
     exit 0
  ;;

  '1')

     if [ -f /root/context ]; then
       . /root/context
     else
       echo "/root/context not found - Unable to source default environment bucket variables"
       exit 1
     fi
     export BUCKETNAME=$pipeline_AppBucketName
     export ACTION=$1
  ;;

  '2')
    export ACTION=$1
    export BUCKETNAME=$2
  ;;
esac

case $ACTION in

  'enable')
     echo "Enabling versioning on S3 Bucket $BUCKETNAME"
     aws s3api put-bucket-versioning --bucket $BUCKETNAME --versioning-configuration Status=Enabled --region $REGION
     EXITCODE=$?
     if [ $EXITCODE -eq 0 ]; then
       echo "Enabled versioning on $BUCKETNAME OK"
       exit $EXITCODE
     else
       echo "Enabling versioning on $BUCKETNAME FAILED"
       exit $EXITCODE
     fi

   ;;

  'suspend')
     echo "Suspending versioning on S3 Bucket $BUCKETNAME"
     aws s3api put-bucket-versioning --bucket $BUCKETNAME --versioning-configuration Status=Suspended --region $REGION
     EXITCODE=$?
     if [ $EXITCODE -eq 0 ]; then
       echo "Suspending versioning on $BUCKETNAME OK"
       exit $EXITCODE
     else
       echo "Suspending versioning on $BUCKETNAME FAILED"
       exit $EXITCODE
     fi
  ;;

  'status')
     echo "The S3 Bucket versioning status on the S3 Bucket $BUCKETNAME is:"
     aws s3api get-bucket-versioning --bucket $BUCKETNAME --region $REGION
  ;;

  *)
    echo "An unknown action was passed to $0 - $ACTION"
    echo "Cannot continue - Please see usage."
    exit 1
  ;;

esac



