#!/usr/bin/env bash

#
# Script test application of S3 trigger functionality
# - Applies the S3 trigger configuration
# - Creates and copies a file to S3 into prefix monitored by the lambda function
# - Removes the S3 trigger configuration

source /etc/profile
source /root/context
source /etc/profile.d/set_qcp_proxy.sh

failed_status=0

function do_fail {
    MSG="$1"
    echo "ERROR: $1..."
    exit 1
}

function do_warn {
    MSG="$1"
    failed_status=1
    echo "WARN: $1..."
}

yum install ruby24 ruby24-devel gcc -y
gem2.4 sources --add http://nexus.qcpaws.qantas.com.au/nexus/repository/gems-all/
gem2.4 sources --remove https://rubygems.org/
gem2.4 sources -c
gem2.4 install bundler --no-document || do_warn "Unable to install bundler"
bundle install -j4

# Add new notification configuration
event_id="${pipeline_Ase}-${pipeline_Branch}-${pipeline_Build}"
input_prefix="${pipeline_Ase}/${pipeline_Branch}/${pipeline_Build}/input"
output_prefix="${pipeline_Ase}/${pipeline_Branch}/${pipeline_Build}/output"
test_file_count=20

echo "Running test on instance_id ${instance_id}..."
MTOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
instance_id=$(/usr/bin/curl -s -m 3-H "X-aws-ec2-metadata-token: $MTOKEN" http://169.254.169.254/latest/meta-data/instance-id)

echo "Adding test configuration trigger from ${pipeline_AppBucketName}"
bundle exec ruby2.4 configure-s3-notifications.rb \
    -b $pipeline_AppBucketName \
    -p $input_prefix \
    -l $lambda_DeployArn \
    -e $event_id \
    -a add || do_warn "Unable to add lambda s3 trigger"

echo "Pausing for the event trigger to be in place"
sleep 120

echo "Creating ${test_file_count} local test files with prefix ${instance_id}_test_n"
for i in {1..20}; do echo "test file" > ${instance_id}_test_${i}; done

aws s3 mv . s3://${pipeline_AppBucketName}/${input_prefix}/ \
    --sse --exclude "*" \
    --include "${instance_id}_test_*" \
    --recursive|| do_warn "Unable to move txt files to s3"

echo "Pausing for the function to warm up"
sleep 60

aws s3 mv s3://${pipeline_AppBucketName}/${output_prefix}/ . \
    --recursive || do_warn "Unable to move txt files from s3"

file_count=$(ls -l ${instance_id}_test_* | wc -l)

# we only care that trigger works, meaning there is one or more files
# lambas might be slower than timeout causing less than expected amount of files at filesystem
if [ ${file_count} -gt 0 ]; then
  echo "Found ${file_count} out of ${test_file_count} files. Lambda trigger works."
else
  do_warn "File count is incorrect. Expecting ${test_file_count}, Found ${file_count}"
fi

echo "Removing test configuration trigger from ${pipeline_AppBucketName}"
bundle exec ruby2.4 configure-s3-notifications.rb \
    -b ${pipeline_AppBucketName} \
    -a remove \
    -e ${event_id} || do_warn "Unable to remove s3 lambda trigger"

echo "Cleaning up remote input test files"
aws s3 rm s3://${pipeline_AppBucketName}/${input_prefix} --recursive

echo "Cleaning up remote output test files"
aws s3 rm s3://${pipeline_AppBucketName}/${output_prefix} --recursive

echo "Cleaning up ${test_file_count} local test files"
rm -f ${instance_id}_test_*

exit ${failed_status}
