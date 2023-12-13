#!/bin/bash
set -e

TIMESTAMP=`date`
REGION="ap-southeast-2"
STREAM_NAME="$kinesis_MyStreamName"

echo -n "Performing put-record on Kinesis stream $STREAM_NAME"
/usr/local/bin/aws --region "$REGION" kinesis put-record --stream-name "$STREAM_NAME"  --data 'hello' --partition-key 'mykey' --cli-binary-format raw-in-base64-out
echo "Done"

echo -n "Ensuring access to Kinesis stream $STREAM_NAME is limited..."
FAILED=0
2>/dev/null /usr/local/bin/aws --region "$REGION" kinesis delete-stream --stream-name "$STREAM_NAME" || FAILED=1
[ $FAILED -eq 1 ] || { echo "Expected access error on delete-stream. Access is incorrectly configured."; exit 1; }
echo "Done"

exit 0
