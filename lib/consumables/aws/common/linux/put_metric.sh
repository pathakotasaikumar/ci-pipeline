#!/usr/bin/env bash
#
# Put a QCP/Custom CloudWatch metric with necessary dimensions
#

if [ $# -eq 3 ]; then
  METRIC_NAME=$1
  VALUE=$2
  UNIT=$3
elif [ $# -eq 2 ]; then
  METRIC_NAME=$1
  VALUE=$2
  UNIT="Count"
else
  (>&2 echo "Usage: put_metric <name> <value> [<units>]")
  exit 1
fi

. /root/context

AMS="$pipeline_Ams"
QDA="$pipeline_Qda"
AS="$pipeline_As"
ASE="$pipeline_Ase"
BRANCH="$pipeline_Branch"
BUILD="$pipeline_Build"
COMPONENT="$pipeline_Component"

# Determine the path to the AWS CLI tools
if [[ -f /usr/local/bin/aws ]]; then
  AWS_CLI="/usr/local/bin/aws"
elif [[ -f /usr/bin/aws ]]; then
  AWS_CLI="/usr/bin/aws"
else
  fail "Unable to locate AWS CLI tools. Cannot continue."
fi

MTOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
REGION=$(curl -s -m 3 -H "X-aws-ec2-metadata-token: $MTOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/.$//')

$AWS_CLI cloudwatch put-metric-data --region "$REGION" --namespace "QCP/Custom" --dimensions "AMSID=$AMS,EnterpriseAppID=$QDA,ApplicationServiceID=$AS,Environment=$ASE,Branch=$BRANCH,Build=$BUILD,Component=$COMPONENT" --metric-name "$METRIC_NAME" --value "$VALUE" --unit "$UNIT"
EXIT_CODE=$?

exit $EXIT_CODE
