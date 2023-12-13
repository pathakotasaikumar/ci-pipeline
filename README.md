# Pipeline

The pipeline tool is designed for QCP and should not be used with other environments without significant re-work.
Current dependencies include a particular AWS setup, QCPAWS domain integration, ServiceNow and other 3rd part services integrations.

## Installation
NOTE: for all installation steps you may need to use `sudo`.

The pipeline requires Ruby 2.2, check that an appropriate version of Ruby is installed:

    >> ruby --version
    ruby 2.3.3p222


Clone repository from Github and install required gems (requires Ruby 2.6)

    git clone git@github.com:qantas-cloud/c031-pipeline.git
    cd pipeline
    bundle install

At this point, there might be an issue with `nokogiri` gem installation.
Just reinstall it separately and try to run `bundle install` again:

    gem install nokogiri
    bundle install

One more try to install nokogiri would be as per [Installing Nokogiri article](http://www.nokogiri.org/tutorials/installing_nokogiri.html).
Follow the article suggestions per OS and target environment.

    sudo apt-get install build-essential patch
    bundle install

**Final checklist**
* `bundle install` works well

## Configuration

The pipeline is designed to be executed by Atlassian Bamboo agents.
Build specific variables are derived from the environment variables injected from the Bamboo Agent job.

It also means that there are some limitations for the local pipeline run such as:
* Environment variables need to be set to emulate bamboo build agent
* `nsupdate/kinit` commands are mocked by empty calls
* Windows domain join won't work unless `bamboo_ad_join_user/bamboo_ad_join_password` are set
* ServiceNow integration won't work unless `bamboo_snow_user/bamboo_snow_password` are set
* A particular AWS role needs to be assumed

### Local development setup

#### Environment variables

The following script configures environment variables that would be set by Bamboo agents during a normal operation.

There are a few extra steps before running the script:
* update `bamboo_planKey` variable with your user id
* ensure `local_dev` is `true` - that way local run won't use ServiceNow
* ensure `local_platform_dir` is set to some folder - local run would use YAML components from this folder instead of `platform` folder

```bash
#!/bin/bash

# Flag to set if the pipeline is the local development mode
# When 'true' , directory nominated via 'local_platform_dir' is used as source for component files.
export local_dev='true'

# Sets location for a local directory that contains component definitions
export local_platform_dir="/pipeline/platform/dev"

##  Bamboo config
# Bamboo plan key - used to derive other build specified parameters such as AMS partner ID, QDA, App Service etc.
# Note: to avoid clashes with other developers, specify unique identifier for application service id
#       Recommendation is to use employee ID number such as 234567 (AMS01-C031S234567DEV)
export bamboo_planKey='AMS01-C031S<NN>DEV'

# Bamboo branch
export bamboo_planRepository_branchName='master'

# Bamboo Build Number
export bamboo_buildNumber='1'

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
# Dev: 'arn:aws:iam::963221539479:role/CD-Control' is used for pipeline development
export bamboo_aws_control_role='arn:aws:iam::963221539479:role/CD-Control'


# Provisioning IAM role to be assumed by the Deployment Role
# Local Credentials / Instance Profile -> CD-Control -> Platform-Provisioning
# Prod: Account specific role name is derived from the account variable
# Dev: arn:aws:iam::963221539479:role/Platform-Provisioning
export bamboo_aws_provisioning_role_name='qcp-platform-provision'

# Prod: SOE id hash - Updated by CSI
# Dev: Local development, copy latest variable value
export bamboo_soe_ami_ids='{ "cis-rhel-7":"ami-77919214" }'

# Prod: qcp-asir-db DynamoDB table in AMS16-prod account
# Dev: qcp-asir-db DynamoDB table in AMS16-nonprod account
export bamboo_asir_dynamodb_table_name='qcp-asir-db'

# Prod: qcp-pipeline S3 bucket in AMS16-prod account
# Dev: qcp-pipeline-dev S3 bucket in AMS16-nonprod account
export bamboo_pipeline_bucket_name='qcp-pipeline-dev'

# Prod: qcp-pipeline-artefacts S3 bucket in AMS16-prod account
# Dev: qcp-pipeline-artefacts-dev S3 bucket in AMS16-nonprod account
export bamboo_artefact_bucket_name='qcp-pipeline-artefacts-dev'

# Active Directory credentials
export bamboo_ad_join_user=<>
export bamboo_ad_join_password=<>

# Service Now Api endpoint
# Prod: https://qantas.service-now.com
# Dev: 'https://qantastest.service-now.com'
export bamboo_snow_endpoint='https://qantastest.service-now.com'

# Service Now credentials
export bamboo_snow_user=<>
export bamboo_snow_password=<>

# Select the AMS16-nonprod Qantas credentials
echo "Selecting credentials file"
cp ~/.aws/credentials-qantas ~/.aws/credentials

# Create fake kinit
echo "Creating dummy kinit command"
cat - <<'EOF' > kinit
#!/bin/bash
echo "STUB - command '$0 $@'"
sleep 1
EOF
chmod +x kinit

# Create fake nsupdate
echo "Creating dummy nsupdate command"
cat - <<'EOF' > nsupdate
#!/bin/bash
echo "STUB - command '$0 $@'"
sleep 2
EOF
chmod +x nsupdate

# Add current directory to path for fake commands
if [[ $PATH != ./* ]]; then
    export PATH=./:$PATH
fi

echo "Done"
```

**Final checklist**
* `rake test` works well and gives green tests
* `rspec_unit_results.html` in the root folder is green

#### Security/AWS Console access
Before the pipeline can be run locally, a few security access changes have to happen.

1) Access to AMS16 noprod account, ability to assume arn:aws:iam::963221539479:role/CD-Control, Platform-Provision role

Use ServiceNow creating new "Service Request" with the following template.
Update `user id`, `name` and `email`:

https://qantas.service-now.com/cloud/ -> General -> Service Request

    	Title: CI/CI pipeline role assume

    	Description: For the pipeline development purposes, the following access to the pipelines ARNs is required:

    	[YOUR-USER-ID], [YOUR-NAME-SURNAME]
    	Email: [YOUR-EMAIL-ADDRESS]

    	User: arn:aws:sts::103380276223:assumed-role/ADFS-User-[YOUR-USER-ID]/[YOUR-USER-ID] should be able to perform sts:AssumeRole on resource: arn:aws:iam::963221539479:role/CD-Control

    	Rohan Jerrems is to approve:
    	rohanjerrems@qantas.com.au

2. Access to AWS Console - AMS16, non-prod

https://qantas.service-now.com/cloud -> Request QCP AWS Console Access
Use the following values:

		Cloud Service Integrator (CSI)
		ReadOnly
		NonPROD

3. Access to 'Pipeline - CD DEV' Bamboo plan

Access to the following bamboo plan is required so that a full pipeline regression testing can be executed.
Normally, access to this plan is provided along with the AWS Console access, but sometimes it might not be a case.

* https://bamboocd.qcpaws.qantas.com.au/browse/AMS01-C031S01DEV

**Final checklist**
* Access to AMS16-nonprod via AWS Console
* Ability to assume a role `arn:aws:iam::963221539479:role/CD-Control, Platform-Provision` - use [role_assume utility](https://github.com/qantas-cloud/c031-saml_assume) for that
* Access to [Pipeline - CD DEV](https://bamboocd.qcpaws.qantas.com.au/browse/AMS01-C031S01DEV) plan

#### role_assume utility
AWS roles can be assumed for the local pipeline run via [role_assume tool](https://git@github.com/qantas-cloud/c031-saml_assume).
This utility helps to get authorized against AWS (including MFA). Once authorized, a AWS access token is stored locally and consumed by the pipeline.
That is how a local pipeline run can be performed under more privileged AWS roles.

#### Executing local pipeline run with rake
An entry point to the pipeline is `rake`, a build utility for Ruby.

Bamboo pipeline execution is split into two steps - CI step and CD step.
Internally, during CI/CD build stages, all calls are redirected to `rake` tasks from `pipeline/tasks` folder.
That means that calling correct rake task locally you would emulate the same Bamboo CI/CD build stage.
Here is a mapping between Bamboo build steps and `rake` tasks:

 Bamboo CI step:
 * `rake upload` -> build artifact in CI

 Bamboo CD step:
  * `rake deploy` -> deploy step in CD
  * `rake release` -> release step in CD
  * `rake teardown` -> teardown step in CD

Once a correct AWS role is assumed, all these `rake` tasks can be run locally as if they were called under Bamboo CI/CD builds.
Be aware that there are more `rake` tasks in the `pipeline/tasks` folder such as `rake clean`, `rake test`.
It is recommended to have a closer look at how all these `rake` tasks work together.

## Developer guidelines

### Source Control / History

* JIRA first - Create detailed JIRA issue for every bug/feature
* Keep changes atomic - Ensure only one bug/feature is addressed per branch
* Branch naming - create a new branch with a name based on JIRA ids.
* Squash commits - development commits for the same feature should be
squashed to a single commit with a multi-line commit message

### Unit Testing
Run unit test suite before any remote push, all tests must pass before the push:

    rake test

NOTE: `rake test` creates a nice HTML report `rspec_unit_results.html` in the root folder. Worth checking!

Individual tests can be invoked via [RSpec](http://rspec.info/):

     rspec spec/unit/consumables/aws/builders/emr_cluster_builder_spec.rb -fd

NOTE: it is suggested to create unit tests for any new code and update existing if needed

**Do not remove any failing tests without investigation or re-write**

### Integration & Functional Testing

There are a few ways to get the pipeline regression  done:
* Partial regression - run onboarded app with your pipeline branch under normal Bamboo build
* Partial regression - run pipeline locally with a limited set of YAML components
* Full regression - run ['Pipeline - CD DEV'](https://bamboocd.qcpaws.qantas.com.au/browse/AMS01-C031S01DEV) plan against the development branch

Here are more details on each of the strategy.

#### Partial regression - onboarder app + your pipeline branch
Required access and setup:
* Ability to modify Bamboo plans
* No local run involved
* Onboarded app components are used

If you have access to modify and manage Bambo plans,
this might be one of the easiest ways to get the pipeline run against an already onboarded app.

Go to the app CI/CD plans, Actions -> Configure plan, and then modify the default repo
for the pipeline pointing to your dev branch.
Once configured, further Bamboo builds would get your pipeline branch instead of master pipeline branch.

This approach can be of use if you already have some apps onboarded.
Build execution is performed on Bamboo agents which don't require local setup at all.

Could be useful to test Windows domain joins, AD/DNS/ServiceNow or other integrations,
long running builds (your laptop need not be always online). Does not require `rake` tasks.

#### Partial regression - local pipeline run
Required access and setup:
* Ability to assume AWS roles
* Local run, configured environment variables
* `local_dev` env var has to be `true`
* `local_platform_dir_dev` env var has to point to a folder with YAML components
* Components from `local_platform_dir_dev` will be used

This is the most common case while developing pipeline features.
Once configured, all components will be loaded from a folder set in `local_platform_dir_dev` env var.

AWS role assume right are required, build is run on your local laptop
(be aware of possible connectivity issues), long running builds can be challenging to wait.

The usual workflow goes as following:
* `rake test` to ensure code base can pass test
* `rake clean` to clean S3 bucket from the previous build
* `rake upload` - build stage, pushes components to S3 bucket
* `rake deploy` - deploy stage, create AWS artifacts
* `rake release` - release stage, make DNS change
* `rake teardown` - teardown stage, cleans up AWS artifacts

#### Full regression - ['Pipeline - CD DEV'](https://bamboocd.qcpaws.qantas.com.au/browse/AMS01-C031S01DEV) execution
This is the ultimate regression testing of the pipeline required before every pull request.

Once development is completed, Run 'Pipeline - CD DEV' plan against the development branch.
* https://bamboocd.qcpaws.qantas.com.au/browse/AMS01-C031S01DEV

In that case, the `pipeline/platform` directory will be used.
This directory contains definitions for all components and combinations.
This allows for the pipeline code to be treated as any other deployable application
that stores it's definitions in the platform directory within its repository.
In a nutshell, we try to emulate users' behavior with pre-defined YAML components covering most of the user cases.

The usual workflow goes as following:

NOTE: Bamboo plan has to be run **twice**, that emulates "component persistence" between builds.

* Build #1 - Deploy
* Build #1 - Release
* Build #2 - Deploy (Tests persistence from build #1)
* Build #2 - Release
* Build #1 - Teardown (Removes non-persisted components from build #1)
* Build #2 - Teardown (with force_teardown_of_released_build set to 'true')

Above steps reproduce a full blue/green cycle experienced by other applications.

Failed stages would indicate an adverse change in functionality that would need to be addressed.
No changes should be merged without successfully completing both unit testing and integration testing.

Mostly, this regression is driven manually via Bamboo web interface.
An average build time is around 40-50 minutes, be aware of that while planning your regression testing.

### User Acceptance testing

With features that are likely to have high impact on users, make codebase available
 for acceptance testing by creating test plans with the pipeline development branch.

### Style Guide

Adhere to Ruby coding style. Use the following guide as a base reference:
* [ruby-style-guide](https://github.com/bbatsov/ruby-style-guide)

Alternatively, you may consider [RubyMine IDE](https://www.jetbrains.com/ruby/) which checks the source code against these rules.
Other means of automation are welcomed as well.

### Branching and Code Review

All work must be developed in feature branches with pull request into master.
Each pull request must be reviewed by at least by one other developer.

** No code with failing Unit or Integration tests should be merged **

### IDEs and additional tooling
Current languages and tooling used:
* [Ruby language](https://www.ruby-lang.org/en/)
* [Rake](https://github.com/ruby/rake) - A make-like build utility for Ruby
* [RSpec](http://rspec.info/) - BDD/TDD for Ruby

You can use your favorite editor with Ruby language support.
However, the following tools are worth considering due to various built-in features:

* [RubyMine](https://www.jetbrains.com/ruby/index.html)
* [Sublime Text](https://www.sublimetext.com/) with additional plugins
* [Visual Studio Code](https://code.visualstudio.com/) with [vscode-ruby](https://github.com/rubyide/vscode-ruby) plugin
* Various setups for vim
* Suggest a new tool here with a PR?

## Feature requests, support and contributions
This project welcomes feedback, suggestions, and improvements.
Use the following channels to raise new ideas or raise issues:

* Join Slack on `#cloud` channel
* Find and talk to QCP guys in `Building C, level 6`
* Send an email to [cloud@qantas.com.au](cloud@qantas.com.au)
* Make a pull request here
* Contribute to [the pipeline docs](https://confluence.qantas.com.au/pages/viewpage.action?pageId=64161715)
* Make a `vagrant` or `docker` image to simplify the current setup

** To overwrite custom_pipeline_branch for pipeline testing use "qantas-cloud/c031-pipeline/actions/ci-action@<BRANCH_NAME>"
** To overwrite any variable, use below in pipeline-build.yaml:
env:
        FOO: bar
        BAX: qux
