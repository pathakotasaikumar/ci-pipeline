#!/usr/bin/env bash

staging_dir=$COMPONENT_DIR/staging
app_dir=python/lib/python3.9/site-packages/
mkdir -p $staging_dir/$app_dir

cp $COMPONENT_DIR/*.py $staging_dir/$app_dir

cd $staging_dir

zip -r $PAYLOAD_DIR/package.zip *
cd $COMPONENT_DIR
rm -rf $staging_dir