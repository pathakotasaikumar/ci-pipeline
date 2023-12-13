#!/bin/bash
echo "autoscale build.sh script"

echo "Collecting all html files into app/html.tar.gz"
cd $COMPONENT_DIR
tar -cvzf $PAYLOAD_DIR/html.tar.gz *.html health

echo "Copying bootstrap.sh to payload directory"
cp $COMPONENT_DIR/bootstrap.sh $PAYLOAD_DIR/
cp $COMPONENT_DIR/schedule.sh $PAYLOAD_DIR/

