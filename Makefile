# This is for local development and CodePipeline only

MKFILE = $(lastword $(MAKEFILE_LIST))
MKFILE_PATH = $(abspath $(MKFILE))
CURRENT_DIR = $(notdir $(patsubst %/,%,$(dir $(MKFILE_PATH))))
ROOT_DIR = $(dir $(MKFILE_PATH))

# Settings defaults
TEST_PATTERN_ARG := $(if $(TEST_PATTERN),--pattern $(TEST_PATTERN),spec/unit)
TEST_COVERAGE_ARG := $(if $(TEST_COVERAGE),bamboo_simplecov_enabled=1 bamboo_simplecov_coverage=83.04)

S3_BUCKET ?= qcp-codepipeline-artefacts
PROJECT_ID ?= ams01-c031-01
QCP_PIPELINE_ASE ?= prod
STACKNAME ?= $(PROJECT_ID)-$(QCP_PIPELINE_ASE)-$(BRANCH_NAME)-dockerbuild
REPOSITORY_NAME ?= $(shell basename `git config --get remote.origin.url` .git)
BRANCH_NAME ?= $(shell git branch | sed -n -e 's/^\* \(.*\)/\1/p')

.PHONY: all aws-check clean deploy release teardown test upload init package upload-package upload-params remove

all: | upload deploy

aws-check:
	$(info Make - Checking if we have any AWS credentials)
	@aws sts get-caller-identity > /dev/null || saml_assume

buildnumber:
	@rake -f $(ROOT_DIR)Rakefile context:last_build |& tail -1

clean:
	$(info Make - Cleaning...)
	@$(MAKE) -f $(MKFILE) aws-check
	rake.sh clean:cloudformation clean

deploy:
	$(info Make - Deploying...)
	@$(MAKE) -f $(MKFILE) aws-check
	bamboo_buildNumber=$(shell expr `rake.sh context:last_build |& tail -1` + 1) && rake.sh deploy

release:
	$(info Make - Releasing...)
	@$(MAKE) -f $(MKFILE) aws-check
	bamboo_buildNumber=$(shell expr `rake.sh context:last_build |& tail -1`) && rake.sh release

rollback:
	$(info Make - Rolling back...)
	@$(MAKE) -f $(MKFILE) aws-check
	rake.sh release

teardown:
	$(info Make - Tearing down...)
	@$(MAKE) -f $(MKFILE) aws-check
	bamboo_buildNumber=$(shell expr `rake.sh context:last_build |& tail -1`) && rake.sh teardown

test:
	$(info Make - Testing...)
	bamboo_pipeline_qa=1 $(TEST_COVERAGE_ARG) bundle exec rspec $(TEST_PATTERN_ARG) --format documentation

upload:
	$(info Make - Uploading...)
	@$(MAKE) -f $(MKFILE) aws-check
	rake.sh upload

init:
	$(info Make - Initialising)
	@$(MAKE) -f $(MKFILE) aws-check
	@$(MAKE) -f $(MKFILE) package
	@$(MAKE) -f $(MKFILE) upload-package
	@$(MAKE) -f $(MKFILE) upload-params
	aws cloudformation create-stack \
	--stack-name $(STACKNAME) \
	--capabilities CAPABILITY_IAM \
	--template-body file://$(ROOT_DIR)deployments/cloudformation/templates/dockerbuild.yaml \
	--parameters ParameterKey=ProjectFriendlyName,ParameterValue=$(REPOSITORY_NAME) \
	ParameterKey=QCPPipelineASE,ParameterValue=$(QCP_PIPELINE_ASE) \
	ParameterKey=ProjectId,ParameterValue=$(PROJECT_ID) \
	ParameterKey=BranchName,ParameterValue=$(BRANCH_NAME)

package:
	$(info Make - Packaging)
	rm -r -f "$(ROOT_DIR)build/*"
	git rev-parse --short=12 HEAD > .gitcommitid
	mkdir -p $(ROOT_DIR)build/
	zip -r $(ROOT_DIR)build/$(REPOSITORY_NAME).zip . --exclude "./.git/*" --exclude "./build/*"
	rm .gitcommitid
	echo "{ \"Parameters\" : \
	{\"ProjectId\" : \"$(PROJECT_ID)\", \
	\"BranchName\" : \"$(BRANCH_NAME)\", \
	\"QCPPipelineASE\" : \"$(QCP_PIPELINE_ASE)\", \
	\"ProjectFriendlyName\" : \"$(REPOSITORY_NAME)\" \
	} }" \
	> "$(ROOT_DIR)build/params.json"
	zip -j -m $(ROOT_DIR)build/params.zip $(ROOT_DIR)build/params.json

upload-package:
	$(info Make - Uploading package)
	aws s3 cp $(ROOT_DIR)build/$(REPOSITORY_NAME).zip s3://$(S3_BUCKET)/cloned-repositories/$(REPOSITORY_NAME)/$(BRANCH_NAME)/$(REPOSITORY_NAME).zip

upload-params:
	$(info Make - Uploading params)
	aws s3 cp $(ROOT_DIR)build/params.zip s3://$(S3_BUCKET)/cloned-repositories/$(REPOSITORY_NAME)/$(BRANCH_NAME)/$(QCP_PIPELINE_ASE)-params.zip

remove:
	$(info Make - Removing)
	@$(MAKE) -f $(MKFILE) aws-check
	aws cloudformation delete-stack \
	--stack-name $(STACKNAME)
