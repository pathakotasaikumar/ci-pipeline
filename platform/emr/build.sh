#!/bin/bash
set -e

cp -R $COMPONENT_DIR/* $PAYLOAD_DIR/

# Ensure bootstrap is executable
chmod +x $PAYLOAD_DIR/bootstrap.sh