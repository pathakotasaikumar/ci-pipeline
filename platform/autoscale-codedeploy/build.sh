#!/bin/bash
echo "autoscale build.sh script"

echo "Collecting all html files into app/html.tar.gz"
cd $COMPONENT_DIR
tar -cvzf $PAYLOAD_DIR/html.tar.gz index.html health

echo "Copying bootstrap.sh to payload directory"
cp $COMPONENT_DIR/bootstrap.sh $PAYLOAD_DIR/
cp $COMPONENT_DIR/schedule.sh $PAYLOAD_DIR/

echo "Copy application artefact to payload directory"
cp -r "${COMPONENT_DIR}/codedeploy_scripts/"* "${PAYLOAD_CODEDEPLOY_DIR}"
cp -r $COMPONENT_DIR/index-codedeploy.html "${PAYLOAD_CODEDEPLOY_DIR}"

echo "Listing CodeDeploy payload contents"
find "${PAYLOAD_CODEDEPLOY_DIR}" -printf "%TY-%Tm-%Td\t%s\t%p\n"