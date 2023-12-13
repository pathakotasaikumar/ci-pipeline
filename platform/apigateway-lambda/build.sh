#!/usr/bin/env bash

staging_dir=$COMPONENT_DIR/staging
mkdir -p $staging_dir

cp -r $COMPONENT_DIR/* $staging_dir

cd $staging_dir
zip -r $PAYLOAD_DIR/package.zip *
cd $COMPONENT_DIR

rm -rf $staging_dir

# Copy code into scan directory for veracode analysis
echo "Scan DIR ${SCAN_DIR}"

mkdir -p $SCAN_DIR/apigateway-lambda
cp -r $COMPONENT_DIR/*.py $SCAN_DIR/apigateway-lambda/