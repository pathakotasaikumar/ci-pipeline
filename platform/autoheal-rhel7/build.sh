#!/bin/bash
echo "autoscale build.sh script"

echo "Collecting all html files into app/html.tar.gz"
cd $COMPONENT_DIR
tar -cvzf $PAYLOAD_DIR/html.tar.gz *.html health

echo "Copying bootstrap.sh to payload directory"
cp $COMPONENT_DIR/bootstrap.sh $PAYLOAD_DIR/

echo "Copying Instance Protection to payload directory"
cp $COMPONENT_DIR/instanceProtection.sh $PAYLOAD_DIR/

echo "Copying apigateway testing file to payload directory"
cp $COMPONENT_DIR/apigatewayAPItesting.sh $PAYLOAD_DIR/

echo "Copying suspend_resume-processes to payload directory"
cp $COMPONENT_DIR/suspend_resume-processes.sh $PAYLOAD_DIR/