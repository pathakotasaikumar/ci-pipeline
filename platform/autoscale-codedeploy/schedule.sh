#!/bin/bash
set -e

echo "creating new schedule in autoscaling group"
MTOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
aws autoscaling put-scheduled-update-group-action \
--auto-scaling-group-name $(aws ec2 describe-instances --instance-ids $(curl -s -H "X-aws-ec2-metadata-token: $MTOKEN" http://169.254.169.254/latest/meta-data/instance-id) --query 'Reservations[*].Instances[*].[Tags[?Key==`aws:autoscaling:groupName`].Value | [0]] ' --output text) \
--scheduled-action-name autoscale-scheduled-action \
--recurrence "0 12 * * MON-SUN" \
--min-size 1 --max-size 1 --desired-capacity 1

exit_code=$?

exit $exit_code