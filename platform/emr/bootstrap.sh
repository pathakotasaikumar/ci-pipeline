#!/bin/bash
set -e

APP_HOME="$HOME/emr_example"
mkdir -p "$APP_HOME"

echo "Sourcing context"
. /home/hadoop/context
. /etc/profile.d/set_qcp_proxy.sh

echo "Copying app files to $APP_HOME"
cp -R /home/hadoop/payload/* $APP_HOME/

# Add metadata tag to EMRFS table to enable sync
EMRFS_TABLENAME=$dynamo_MyTableName
TIMESTAMP=`date +%s`
sed -i "s#%TIMESTAMP%#${TIMESTAMP}#g" "$APP_HOME/MultiKeyStoreTag.json"
cat "$APP_HOME/MultiKeyStoreTag.json"
aws dynamodb put-item --table-name $EMRFS_TABLENAME --item "file://$APP_HOME/MultiKeyStoreTag.json" --region ap-southeast-2

echo "Ensuring we can access our artefacts"
cat $APP_HOME/test_file

echo -n "Performing describe-cluster on EMR cluster"
aws emr describe-cluster --cluster-id $(cat /mnt/var/lib/info/job-flow.json | jq -r '.jobFlowId') --region ap-southeast-2
echo "Done"

exit 0