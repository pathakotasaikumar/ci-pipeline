#!/usr/bin/env bash

echo '[Pipeline rake wrapper] - Init'

Red='\033[0;31m'
Green='\033[0;32m'
NC='\033[0m'
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $DIR/..

# QCPP-1025
# Toggle between system installed version and rbenv
if [ -x "$(command -v rbenv)" ]; then
    echo -e "${Green}Using rbenv ruby${NC}"
    ./bin/pipeline_bundle.sh
else
    echo -e "${Green}Using System Ruby${NC}"
    # Enable Ruby 2.2 SCL
    . /opt/rh/rh-ruby22/enable
fi


# Switch to the custom pipeline branch(QCPFB-101)
if [ -n "$bamboo_custom_pipeline_branch" ]; then
    echo -e "${Green}Switching to custom pipeline branch :- $bamboo_custom_pipeline_branch${NC}"
    sh -c "git checkout $bamboo_custom_pipeline_branch 2>/dev/null"
    if [ $? -ne 0 ]; then
        echo -e "${Red}Unable to find the branch($bamboo_custom_pipeline_branch) in pipeline repository.${NC}"
        exit 1
    fi
else
    echo -e "${Green}Using pipeline branch :- master"
fi

# trace commit and its url for better troubleshooting experience.
REPO_BASE_URL="https://github.com/qantas-cloud/c031-pipeline/commit"
REPO_COMMIT=$(sh -c 'git rev-parse HEAD')
REPO_COMMIT_URL="$REPO_BASE_URL/$REPO_COMMIT"

echo -e "${Green}   - commit    : $REPO_COMMIT${NC}"
echo -e "${Green}   - commit url: $REPO_COMMIT_URL${NC}"

# execute rake task
if [ -x "$(command -v rbenv)" ]; then
    bundle exec rake -f ./Rakefile "$@"
else
    rake -f ./Rakefile "$@"
fi
EXIT_CODE=$?

# change ownership of all files to bamboo to allow automatic cleanup
# Need to protect output, some rake command need the last line
chown -R bamboo:bamboo * > /dev/null 2>&1
cd - > /dev/null

exit $EXIT_CODE
