#!/bin/bash
set -e

EXPECTED="succeeded!"
nc -z -v -w5 $sqlserver_DatabaseDeployDnsName $sqlserver_DatabaseEndpointPort | cut -d ' ' -f 7
if [ $? -ne 0 ];then
    exit 1
else
    echo "$EXPECTED"
fi
