#!/bin/bash

# The pipeline populates these variables
AWS_PROXY="<| AwsProxy |>"

if [ -z "$AWS_PROXY" ]; then
  unset HTTP_PROXY HTTPS_PROXY NO_PROXY http_proxy https_proxy no_proxy
else
  export HTTP_PROXY="$AWS_PROXY"
  export HTTPS_PROXY="$AWS_PROXY"
  export NO_PROXY="<| NoProxy |>"
  export http_proxy="$HTTP_PROXY"
  export https_proxy="$HTTPS_PROXY"
  export no_proxy="$NO_PROXY"
fi
