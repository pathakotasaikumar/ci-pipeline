#!/bin/bash
echo "test-instance build.sh script"

echo "Copying scripts to payload directory"
cp $COMPONENT_DIR/test.sh $PAYLOAD_DIR/

mkdir -p $PAYLOAD_DIR/tests

mkdir -p $PAYLOAD_DIR/.test_folder
cat "test" > $PAYLOAD_DIR/.test_folder/.test_file

cp -R $COMPONENT_DIR/. $PAYLOAD_DIR
