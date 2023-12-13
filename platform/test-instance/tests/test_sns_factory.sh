#!/bin/bash
set -e

REGION="ap-southeast-2"
TOPIC_PREFIX="$sns_factory_MySnsFactoryTopicPrefix"
TOPIC_ARN_PREFIX="$sns_factory_MySnsFactoryTopicArnPrefix"

echo -n "Create SNS Topic $TOPIC_PREFIX-test-topic"
aws --region "$REGION" sns create-topic --name "$TOPIC_PREFIX-test-topic"
echo "Done"

sleep 5
echo -n "Delete SNS Topic $TOPIC_PREFIX-test-topic"
aws --region "$REGION" sns delete-topic --topic-arn "$TOPIC_ARN_PREFIX-test-topic"
echo "Done"

sleep 5
echo -n "List SNS Topics"
aws --region "$REGION" sns list-topics
echo "Done"

echo -n "Ensuring access to sns factory $TOPIC_PREFIX is limited..."
FAILED=0
2>/dev/null aws --region "$REGION" sns create-topic --name test-topic-failure || FAILED=1
[ $FAILED -eq 1 ] || { echo "Expected access error on create topic outside of prefix scope. Access is incorrectly configured."; exit 1; }
echo "Done"

exit 0
