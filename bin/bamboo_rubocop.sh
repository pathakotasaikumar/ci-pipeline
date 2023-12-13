#!/usr/bin/env bash
set -x

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $DIR/..

if [ -x "$(command -v rbenv)" ]; then
    echo -e "${Green}Using rbenv ruby${NC}"
    ./bin/pipeline_bundle.sh
fi

export bamboo_pipeline_qa=1
bundle exec rake qa:rubocop --trace

EXIT_CODE=$?

cd -
exit $EXIT_CODE
