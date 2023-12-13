echo "[Pipeline config] - setting up local environment variables"

# Ensuring that pipeline uses the updated folder structure for applications
export container_execution='true'

##  Bamboo config
# Bamboo plan key - used to derive other build specified parameters such as AMS partner ID, QDA, App Service etc.
# Note: to avoid clashes with other developers, specify unique identifier for application service id
#       Recommendation is to onboard your own QAS application ID for now instead of User ID as the
#       onboarding UI does not allow 6 digits QAS
export qcp_pipeline_ams=${qcp_pipeline_ams:=AMS16}
export qcp_pipeline_qda=${qcp_pipeline_qda:=P000}
export qcp_pipeline_qas=${qcp_pipeline_qas:=01}
export qcp_pipeline_ase=${qcp_pipeline_ase:='DEV'}
export bamboo_shortPlanKey="${qcp_pipeline_qda}S${qcp_pipeline_qas}${qcp_pipeline_ase}"
export bamboo_planKey="${qcp_pipeline_ams}-${bamboo_shortPlanKey}"

# Bamboo branch
export bamboo_planRepository_branchName=${planRepository_branchName:='master'}

# Bamboo Build Number
export bamboo_buildNumber=${buildNumber:=1}

# Duplicate the build dir variable
export bamboo_build_working_directory=$BUILD_DIR

# Bamboo Deployment Environment
export bamboo_deployment_env=${deployment_env:=NonProduction}

# Skip teardown of failed builds (useful for troubleshooting failed bootstraps)
export bamboo_cleanup_after_deploy_failure=${cleanup_after_deploy_failure:=true}

# Skip call out to ServiceNow api for lifecycle management
# Prod: false
# Dev: true
export bamboo_skip_alm=${skip_alm:=true}

## AWS config
# QCP proxy setting is deployed
export bamboo_aws_proxy='http://proxy.qcpaws.qantas.com.au:3128'

# Target AWS Region
export bamboo_aws_region='ap-southeast-2'

# Target AWS account used for deployment
# Prod: Variable set as s plan variable onboarding from CMDB
# Dev: 963221539479 (AMS16-nonprod) is used for pipeline development
export bamboo_aws_account_id=${aws_account_id:=963221539479}

# Target AWS account used for deployment
# Production: Variable set as s plan variable onboarding from CMDB
# Default: 'vpc-e719bf80' is used for pipeline development
export bamboo_aws_vpc_id=${aws_vpc_id:=vpc-e719bf80}

# Deployment IAM role to be assumed for deployment
# Prod: Variable set as s plan variable onboarding from CMDB
# Dev: 'arn:aws:iam::695837244598:role/CD-Control' is used for pipeline development
export bamboo_aws_control_role=${aws_control_role:='arn:aws:iam::695837244598:role/CD-Control'}

# Provisioning IAM role to be assumed by the Deployment Role
# Local Credentials / Instance Profile -> CD-Control -> Platform-Provisioning
# Prod: Account specific role name is derived from the account variable
# Dev: arn:aws:iam::963221539479:role/Platform-Provisioning
export bamboo_aws_provisioning_role_name=${aws_provisioning_role_name:=qcp-platform-provision}

# DR account
export bamboo_dr_account_id=${dr_account_id:=006642828360}

# Prod: SOE id hash - Updated by CSI
# Dev: Local development, copy latest variable value
# comes from SSM, don't need it here anymore
# export bamboo_soe_ami_ids='{ "cis-rhel-7":"ami-77919214" }'

# Prod: qcp-asir-db DynamoDB table in AWS-13 account
# Dev: qcp-asir-db DynamoDB table in AWS-12 account
export bamboo_asir_dynamodb_table_name=${asir_dynamodb_table_name:='qcp-asir-db-prod'}

# Prod: qcp-pipeline S3 bucket in AWS-13 account
# Dev: qcp-pipeline-dev S3 bucket in AWS-12 account
export bamboo_pipeline_bucket_name=${pipeline_bucket_name:='qcp-pipeline'}

# Prod: qcp-pipeline-artefacts S3 bucket in AWS-13 account
# Dev: qcp-pipeline-artefacts-dev S3 bucket in AWS-12 account
export bamboo_artefact_bucket_name=${artefact_bucket_name:='qcp-pipeline-artefacts'}

# Service Now Api endpoint
# Prod: https://qantas.service-now.com
# Dev: 'https://qantastest.service-now.com'
export bamboo_snow_endpoint=${snow_endpoint:='https://qantas.service-now.com'}

# Trend DSM URL
export bamboo_trend_dsm_url=${trend_dsm_url:='https://trenddsm.qcpaws.qantas.com.au'}


echo "[Pipeline config] - done!"

echo "
---------- Here are some tips & tricks ---------------------

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
