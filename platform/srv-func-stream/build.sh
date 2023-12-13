#!/usr/bin/env bash

staging_dir=$COMPONENT_DIR/staging
mkdir -p $staging_dir

cp $COMPONENT_DIR/*.py $staging_dir

cd $staging_dir
zip -r $PAYLOAD_DIR/package.zip *
cd $COMPONENT_DIR

rm -rf $staging_dir

mkdir -p $SCAN_DIR/srv-func-stream
cp -r $COMPONENT_DIR/*.py $SCAN_DIR/srv-func-stream/