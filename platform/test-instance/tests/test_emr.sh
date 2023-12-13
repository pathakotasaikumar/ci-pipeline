#!/bin/bash
set -e

TIMESTAMP=`date`
REGION="ap-southeast-2"
CLUSTER_ID="$emr_MyClusterId"

echo -n "Performing list-instances on EMR cluster $CLUSTER_ID"
/usr/local/bin/aws --region "$REGION" emr list-instances --cluster-id "$CLUSTER_ID" > output
echo "Done"

echo -n "Performing describe-cluster on EMR cluster $CLUSTER_ID"
/usr/local/bin/aws --region "$REGION" emr describe-cluster --cluster-id "$CLUSTER_ID" > output
echo "Done"

echo -n "Ensuring EMR cluster access is limited..."
FAILED=0
2>/dev/null /usr/local/bin/aws --region "$REGION" emr terminate-clusters --cluster-ids "$CLUSTER_ID" || FAILED=1
[ $FAILED -eq 1 ] || { echo "Expected access error on terminate-clusters. Access is incorrectly configured."; exit 1; }
echo "Done"

exit 0
