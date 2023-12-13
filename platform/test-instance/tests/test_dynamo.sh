#!/bin/bash
set -e

TIMESTAMP=`date`
REGION="ap-southeast-2"
TABLE_NAME="$dynamo_MyTableName"

echo -n "Performing put-item on DynamoDB table $TABLE_NAME"
/usr/local/bin/aws --region "$REGION" dynamodb put-item --table-name "$TABLE_NAME" --item '{"hashKey": {"S": "MyItem"}, "rangeKey": {"S": "SortMe"}}'
echo "Done"

echo -n "Ensuring access to DynamoDB table $TABLE_NAME is limited..."
FAILED=0
2>/dev/null /usr/local/bin/aws --region "$REGION" dynamodb delete-table --table-name "$TABLE_NAME" || FAILED=1
[ $FAILED -eq 1 ] || { echo "Expected access error on delete-table. Access is incorrectly configured."; exit 1; }
echo "Done"

exit 0
