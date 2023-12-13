#!/bin/bash
if [[ ! -z $1 ]]; then
  user_id=$1
else
  user_id=$USER_ID
fi

# helper methods
function validate_exit_code()
{
    CODE=$1
    MGS=$2

    [ $CODE -eq 0 ] && echo "Exit code is 0, continue..."
    [ $CODE -ne 0 ] && echo "Exising with non-zero code [$CODE] - $MGS" && exit $CODE
}

echo "[Pipeline config] - setting up local environment variables"
echo "  Using USER_ID: $user_id"

if [[ -z $user_id ]]; then
  echo 'USER_ID variable is null or empty, it should be your Qantas ID number'
  echo '  - pass as an argumet to this script'
  echo '  - use $USER_ID environment variable'
  echo '  - with Docker, use docker run -e USER_ID=211238 -i -t -v $(pwd):/BUILD_DIR/pipeline --entrypoint=/bin/bash qcp/pipeline:latest'

  echo 'Exiting -1'

  exit -1
fi

# Flag to set if the pipeline is the local development mode
# When 'true' , directory nominated via 'local_platform_dir' is used as source for component files.
export local_dev='true'

# This ain't pretty - service now restrict to 5 number max on app and service ID so we split the user ID up
fake_qda=U${user_id:0:3}
fake_qas=${user_id:3}

##  Bamboo config
# Bamboo plan key - used to derive other build specified parameters such as AMS partner ID, QDA, App Service etc.
# Note: to avoid clashes with other developers, specify unique identifier for application service id
#       Recommendation is to onboard your own QAS application ID for now instead of User ID as the
#       onboarding UI does not allow 6 digits QAS
export qcp_pipeline_ams=${qcp_pipeline_ams:='AMS16'}
export qcp_pipeline_qda=${qcp_pipeline_qda:=$fake_qda}
export qcp_pipeline_qas=${qcp_pipeline_qas:=$fake_qas}
export qcp_pipeline_ase=${qcp_pipeline_ase:='DEV'}
export bamboo_shortPlanKey="${qcp_pipeline_qda}S${qcp_pipeline_qas}${qcp_pipeline_ase}"
export bamboo_planKey="${qcp_pipeline_ams}-${bamboo_shortPlanKey}"

# Bamboo branch
export bamboo_planRepository_branchName=${bamboo_planRepository_branchName:='master'}

# Bamboo Build Number
export bamboo_buildNumber='1'

# Duplicate the build dir variable
export bamboo_build_working_directory=$BUILD_DIR

# Bamboo Deployment Environment
export bamboo_deployment_env='NonProduction'

# Skip teardown of failed builds (useful for troubleshooting failed bootstraps)
export bamboo_cleanup_after_deploy_failure="true"

# Skip call out to ServiceNow api for lifecycle management
# Prod: false
# Dev: true
export bamboo_skip_alm='true'

## AWS config
# QCP proxy setting is deployed
export bamboo_aws_proxy='http://proxy.qcpaws.qantas.com.au:3128'

# Target AWS Region
export bamboo_aws_region='ap-southeast-2'

# Target AWS account used for deployment
# Prod: Variable set as s plan variable onboarding from CMDB
# Dev: 963221539479 (AMS16-nonprod) is used for pipeline development
export bamboo_aws_account_id='963221539479'

# Target AWS account used for deployment
# Production: Variable set as s plan variable onboarding from CMDB
# Default: 'vpc-e719bf80' is used for pipeline development
export bamboo_aws_vpc_id='vpc-e719bf80'

# Deployment IAM role to be assumed for deployment
# Prod: Variable set as s plan variable onboarding from CMDB
# Dev: 'arn:aws:iam::695837244598:role/CD-Control' is used for pipeline development
export bamboo_aws_control_role='arn:aws:iam::695837244598:role/CD-Control'

# Provisioning IAM role to be assumed by the Deployment Role
# Local Credentials / Instance Profile -> CD-Control -> Platform-Provisioning
# Prod: Account specific role name is derived from the account variable
# Dev: arn:aws:iam::963221539479:role/Platform-Provisioning
export bamboo_aws_provisioning_role_name='qcp-platform-provision'

# DR account
export bamboo_dr_account_id='006642828360'

# Prod: SOE id hash - Updated by CSI
# Dev: Local development, copy latest variable value
# comes from SSM, don't need it here anymore
# export bamboo_soe_ami_ids='{ "cis-rhel-7":"ami-77919214" }'

# Prod: qcp-asir-db DynamoDB table in AWS-13 account
# Dev: qcp-asir-db DynamoDB table in AWS-12 account
export bamboo_asir_dynamodb_table_name='qcp-asir-db'

# Prod: qcp-pipeline S3 bucket in AWS-13 account
# Dev: qcp-pipeline-dev S3 bucket in AWS-12 account
export bamboo_pipeline_bucket_name='qcp-pipeline-dev'

# Prod: qcp-pipeline-artefacts S3 bucket in AWS-13 account
# Dev: qcp-pipeline-artefacts-dev S3 bucket in AWS-12 account
export bamboo_artefact_bucket_name='qcp-pipeline-artefacts-dev'

# Service Now Api endpoint
# Prod: https://qantas.service-now.com
# Dev: 'https://qantastest.service-now.com'
export bamboo_snow_endpoint='https://qantastest.service-now.com'

# Service Now credentials
export bamboo_snow_user=''
export bamboo_snow_password=''

# Trend DSM URL
export bamboo_trend_dsm_url='https://trenddsm.qcpaws.qantas.com.au'

# Since this is for local development only, switch to QA mode
export bamboo_pipeline_qa=1

# Create fake kinit
echo "  Creating dummy kinit command"
cat - <<'EOF' > kinit
#!/bin/bash
echo "STUB - command '$0 $@'"
sleep 0.01
EOF
chmod +x kinit

# Create fake nsupdate
echo "  Creating dummy nsupdate command"
cat - <<'EOF' > nsupdate
#!/bin/bash
echo "STUB - command '$0 $@'"
sleep 0.01
EOF
chmod +x nsupdate

# Create fake setx / net
# These are needed for Pester based testing of PS scripts
echo "  Creating dummy setx command"
cat - <<'EOF' > setx
#!/bin/bash
echo "STUB - command '$0 $@'"
sleep 0.1
EOF
chmod +x setx

echo "  Creating dummy setx command"
cat - <<'EOF' > net
#!/bin/bash
echo "STUB - command '$0 $@'"
sleep 0.1
EOF
chmod +x net

echo "  Creating dummy cfn-signal.exe command"
cat - <<'EOF' > cfn-signal.exe
#!/bin/bash
echo "STUB - command '$0 $@'"
sleep 0.1
EOF
chmod +x cfn-signal.exe

echo "  Creating dummy cfn-get-metadata command"
cat - <<'EOF' > cfn-get-metadata
#!/bin/bash
echo "STUB - command '$0 $@'"
sleep 0.1
EOF
chmod +x cfn-get-metadata

# Add current directory to path for fake commands
if [[ $PATH != ./* ]]; then
  export PATH=./:$PATH
fi

# Active Directory credentials
# this now fetched by SSM, we don't need these
#export bamboo_ad_join_user=''
#export bamboo_ad_join_password=''
unset ad_join_user && unset bamboo_ad_join_user
unset ad_join_password && unset bamboo_ad_join_password

# aws_proxy/bamboo_aws_proxy ENV variables are used in unit tests
# pipeline local runs should unset these variables as needed
# unset aws_proxy && unset bamboo_aws_proxy

unset asir_dynamodb_table_name && unset bamboo_asir_dynamodb_table_name
unset snow_user && unset bamboo_snow_user
unset snow_password && unset bamboo_snow_password
unset snow_endpoint && unset bamboo_snow_endpoint

# rbenv
eval "$(rbenv init -)"

# pre-creating default ~/.saml config for saml_assume
echo "  Creating a default ~/.saml for saml_assume"
cat > ~/.saml <<EOL
default:
  IDP_LOGIN_URL: https://sts1.qantas.com.au/adfs/ls/IdpInitiatedSignOn.aspx?loginToRp=urn:amazon:webservices
  SAML_USERNAME: CORP\\${user_id}
  SAML_ROLE: arn:aws:iam::695837244598:role/QCP-NonProdBuildTeam
  HTTP_PROXY: None
EOL
chmod +x ~/.saml

echo "[Pipeline config] - done!"

echo "
---------- Here are some tips & trick ---------------------

# check pipeline environment variable setup
printenv | sort | grep bamboo

# run ALL pipeline tests with/without logs
rspec spec/unit --format documentation
bamboo_disable_log_output=1 rspec spec/unit --format documentation

# run ALL pipeline tests with performance profiling and stat
rspec spec/unit --format documentation --profile

# run guard, continuous tests on file changes
guard -G Guardfile-simplecov.rb

# run SPECIFIC tests
rspec --pattern **/aws_instance** --format documentation
rspec --pattern **/aws_sns_factory** --format documentation

# run ALL pipeline tests via Rake (report is rspec_unit_results.html)
rake test

# run SimpleCov unit test coverage (report is target/site/clover/)
export bamboo_simplecov_enabled=1 && export bamboo_simplecov_coverage=83.04 && rake test --trace

# run RuboCop (report is logs/rubocop_report.html)
export bamboo_pipeline_qa=1 && rake qa:rubocop

# run YardStick (report is logs/yardstick_report.txt
export bamboo_pipeline_qa=1 && export bamboo_yardstick_threshold=65.3 && rake qa:yardstick --trace

# executing powershell unit tests
pwsh -c \"Invoke-Pester -Script @{ Path = 'spec_ps/unit/consumables/aws/aws_autoscale/windows-deploy.Tests.ps1'; } -EnableExit\"
pwsh -c \"Invoke-Pester -Script @{ Path = 'spec_ps/unit/consumables/aws/common/windows/windeploy.Tests.ps1'; } -EnableExit\"

# executing powershell unit tests in target folder
pwsh -c \"Invoke-Pester -Script @{ Path = 'spec_ps/unit/consumables/aws/**/*.Tests.ps1'; } -EnableExit\"
pwsh -c \"Invoke-Pester -Script @{ Path = 'spec_ps/unit/consumables/aws/common/windows/*.Tests.ps1'; } -EnableExit\"

# run saml_assume
saml_assume

# run aws cli after saml_assume
aws s3 ls

-----------------------------------------------------------
"
