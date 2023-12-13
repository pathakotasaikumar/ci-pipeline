#!/bin/bash
set -e

TIMESTAMP=`date`
REGION="ap-southeast-2"
VOLUME_ID="$volume_rhel6_MyVolumeId"
MTOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=`curl -s -H "X-aws-ec2-metadata-token: $MTOKEN" http://169.254.169.254/latest/meta-data/instance-id`

echo -n "Attaching volume $VOLUME_ID..."
/usr/local/bin/aws --region "$REGION" ec2 attach-volume --volume-id "$VOLUME_ID" --instance-id "$INSTANCE_ID" --device /dev/sdv > output
echo "Done"

sleep 5
echo -n "Detaching volume $VOLUME_ID..."
/usr/local/bin/aws --region "$REGION" ec2 detach-volume --volume-id "$VOLUME_ID" --instance-id "$INSTANCE_ID" > output
echo "Done"

echo -n "Ensuring access to volume $VOLUME_ID is limited..."
FAILED=0
2>/dev/null /usr/local/bin/aws --region "$REGION" ec2 delete-volume --volume-id "$VOLUME_ID" || FAILED=1
[ $FAILED -eq 1 ] || { echo "Expected access error on delete-volume. Access is incorrectly configured."; exit 1; }
echo "Done"

exit 0
