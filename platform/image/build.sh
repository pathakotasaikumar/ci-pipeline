#!/bin/bash
echo "test-instance build.sh script"

echo "Copying bootstrap.sh to payload directory"
cp $COMPONENT_DIR/* $PAYLOAD_DIR/
