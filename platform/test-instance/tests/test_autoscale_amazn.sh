#!/bin/bash
set -e

URL="$autoscale_amzn_DeployDnsName"

echo "Testing URL: http://$URL"
STATUS_CODE=$(curl -s --output /dev/null --write-out "%{http_code}" "http://$URL")
echo "Received status code $STATUS_CODE"
[ "$STATUS_CODE" = "200" ] || exit 1

exit 0