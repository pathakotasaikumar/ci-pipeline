#!/bin/bash
set -e

echo "Testing connectivity to Redis endpoint \"$redis_MyCachePrimaryEndPointAddress\" on port $redis_MyCachePrimaryEndPointPort..."
FAILED=0
nc -z -v -w5 $redis_MyCachePrimaryEndPointAddress $redis_MyCachePrimaryEndPointPort || FAILED=1
[ $FAILED -eq 0 ] || { echo "Failed to connect to Redis port"; exit 1; }
echo "Done"
