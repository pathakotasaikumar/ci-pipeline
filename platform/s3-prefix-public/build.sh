#!/bin/bash

# The following variable are available in the environment:
#   $COMPONENT_DIR: Component directory (directory of build.sh)
#   $PAYLOAD_DIR: Payload directory (copy artefact files here)
#   $APP_DIR: repository root directory

echo "Copying scripts to the payload directory"
cp -r $COMPONENT_DIR/content/* $PAYLOAD_DIR/