#!/usr/bin/env bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $DIR/..

if [[ ! -z $1 ]]; then USER_ID=$1; else USER_ID=$USER_ID; fi
RUBY_VERSION=$(<.ruby-version)

TAG_NAME="qcp/pipeline:ruby-$RUBY_VERSION"

docker run \
    --rm -it -e USER_ID=$USER_ID \
    -v $(PWD):/build-dir/pipeline \
    -v $2:/build-dir/app \
    $TAG_NAME bash

cd -