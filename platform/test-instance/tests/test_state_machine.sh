#!/bin/bash
set -e

echo -n "#testing the DNS TXT value exists in $state_machine_DeployDnsName"
ARN=`dig $state_machine_DeployDnsName TXT +short` && ARN="${ARN%\"}" && ARN="${ARN#\"}"
echo "Done"

echo -n "invoke the state machine with ARN $ARN"
aws stepfunctions start-execution --state-machine-arn $ARN || exit 1
echo "Done"

exit 0