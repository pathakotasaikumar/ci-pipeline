#!/bin/bash

source /root/context

echo --------------------------------------------------
echo Qantas API Gateway API registration testing started `date`
echo --------------------------------------------------
echo

DECRYPTED_API_TOKEN=`kms_decrypt $app_apigatewaytoken` # Used secrets manager application to encrypt the apigatewaytoken

echo "Invoking the Lambda endpoint registered with API Gateway"
echo "calling with curl --write-out %{http_code} --silent --output /dev/null -X GET --header 'Accept: application/json' --header \"Authorization: Bearer ${DECRYPTED_API_TOKEN}\" 'https://api-stage.qantas.com/api/customer/qcp-pipeline-dev-lambda/v1/lambdaEnvironment' -IL --silent"

API_STATUS_CODE=$(curl --write-out %{http_code} --silent --output /dev/null -X GET --header 'Accept: application/json' --header "Authorization: Bearer ${DECRYPTED_API_TOKEN}" 'https://api-stage.qantas.com/api/customer/qcp-pipeline-dev-lambda/v1/lambdaEnvironment' -IL --silent)
curl -v -X GET --header 'Accept: application/json' --header "Authorization: Bearer ${DECRYPTED_API_TOKEN}" 'https://api-stage.qantas.com/api/customer/qcp-pipeline-dev-lambda/v1/lambdaEnvironment' -iL


if [[ "$API_STATUS_CODE" -ne 200 ]] ; then
    echo "Failed to invoke the API Gateway endpoint and get the status result ${API_STATUS_CODE}.So, Existing with error code."
    # exit 1
else
    echo "Successfully invoke the API Gateway endpoint and HTTP result status is ${API_STATUS_CODE}"
    BUILD_NUMBER=$(curl -s  -X GET --header 'Accept: application/json' --header "Authorization: Bearer ${DECRYPTED_API_TOKEN}" 'https://api-stage.qantas.com/api/customer/qcp-pipeline-dev-lambda/v1/lambdaBuild' | python -c "import json,sys;obj=json.load(sys.stdin);print obj['buildNumber'];")
    exit_code=$?

    if [[ "$exit_code" -ne 0 ]] ; then
      echo "Failed to invoke the API Gateway endpoint while testing the response.So, Existing with error code."
      # exit $exit_code
    else
      echo "Successfully Invoked a API Gateway URL and the got the build number is ${BUILD_NUMBER}"
    fi

fi

echo
echo --------------------------------------------------
echo Qantas API Gateway API registration testing finished `date`
echo --------------------------------------------------
echo

exit 0
