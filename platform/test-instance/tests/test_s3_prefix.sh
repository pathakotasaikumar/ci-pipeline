#!/bin/bash
set -e

REGION="ap-southeast-2"
CONTENT_PATH="content/index.html"
ASE="$pipeline_Ase"
PUBLIC_BUCKET=""
if [ "$ASE" == "dev" ]
then 
    PUBLIC_BUCKET="qf-static-public-nonprod01"
else
    PUBLIC_BUCKET="qf-static-public-prod01"
fi

DEPLOY_PATH="$s3_prefix_DeployPrefixPath"
RELESE_PATH="$s3_prefix_ReleasePrefixPath"

echo "Testing Deployment S3 location"

CURL_DEPLOY=`curl https://s3-$REGION.amazonaws.com/$PUBLIC_BUCKET/$DEPLOY_PATH/$CONTENT_PATH `
echo $CURL_DEPLOY

echo "Tesing Release S3 location"

CURL_RELEASE=`curl https://s3-$REGION.amazonaws.com/$PUBLIC_BUCKET/$RELESE_PATH/$CONTENT_PATH `
echo $CURL_RELEASE


exit 0
