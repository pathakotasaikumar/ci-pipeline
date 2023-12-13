#!/usr/bin/env bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $DIR/..

if [[ ! -z $1 ]]; then USER_ID=$1; else USER_ID=$USER_ID; fi
RUBY_VERSION=$(<.ruby-version)

TAG_NAME="qcp/pipeline:ruby-$RUBY_VERSION"

echo "Building pipeline Docker container, tag: $TAG_NAME"
docker build . --tag $TAG_NAME \
      --build-arg BUILD_DATE=`date -u +"%Y-%m-%dT%H:%M:%SZ"` \
      --build-arg RUBY_VERSION=$RUBY_VERSION 