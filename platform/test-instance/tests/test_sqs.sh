#!/bin/bash
set -e

TIMESTAMP=`date`
REGION="ap-southeast-2"
ENDPOINT="$sqs_MyQueueEndpoint"

echo -n "Pushing messages into SQS queue $ENDPOINT..."
MESSAGE_BODY="My Message $TIMESTAMP"
/usr/local/bin/aws --region "$REGION" sqs send-message --queue-url "$ENDPOINT" --message-body "$MESSAGE_BODY" > output
echo "Done"

echo -n "Retrieving message from SQS queue $ENDPOINT..."
/usr/local/bin/aws --region "$REGION" sqs receive-message --queue-url "$ENDPOINT" --output text > output
MESSAGE=`cat output | grep "Message" | awk -F'\t' '{ print $2 }'`
HANDLE=`cat output | grep "Message" | awk -F'\t' '{ print $5 }'`
[ "$MESSAGE" = "$MESSAGE_BODY" ] || { echo "Expected to receive '$MESSAGE_BODY', but received '$MESSAGE'"; exit 1; }
echo "Done"

echo -n "Deleting message from SQS queue $ENDPOINT..."
/usr/local/bin/aws --region "$REGION" sqs delete-message --queue-url "$ENDPOINT" --receipt-handle "$HANDLE"
echo "Done"

echo -n "Ensuring access to SQS queue $ENDPOINT is limited..."
FAILED=0
2>/dev/null /usr/local/bin/aws --region "$REGION" sqs delete-queue --queue-url "$ENDPOINT" || FAILED=1
[ $FAILED -eq 1 ] || { echo "Expected access error on delete-queue. Access is incorrectly configured."; exit 1; }
echo "Done"

exit 0
