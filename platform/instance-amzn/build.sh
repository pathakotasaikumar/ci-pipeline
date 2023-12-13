#!/usr/bin/env bash

echo "autoscale build.sh script"

echo "Collecting all html files into app/html.tar.gz"
cd $COMPONENT_DIR

echo "Copying bootstrap.sh to payload directory"
cp -R $COMPONENT_DIR/* $PAYLOAD_DIR/

# Copy code into scan directory for veracode analysis
echo "Scan DIR ${SCAN_DIR}"

mkdir -p $SCAN_DIR/app
mkdir -p $SCAN_DIR/scripts
cp -r $COMPONENT_DIR/app/* $SCAN_DIR/app/
cp -r $COMPONENT_DIR/scripts/* $SCAN_DIR/scripts/