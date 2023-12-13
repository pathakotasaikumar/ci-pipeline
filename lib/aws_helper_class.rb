require 'aws-sdk'
require_relative 'aws_helpers/autoscaling_helper'
require_relative 'aws_helpers/cloudformation_helper'
require_relative 'aws_helpers/dynamodb_helper'
require_relative 'aws_helpers/ec2_helper'
require_relative 'aws_helpers/elasticache_helper'
require_relative 'aws_helpers/iam_helper'
require_relative 'aws_helpers/kinesis_helper'
require_relative 'aws_helpers/lambda_helper'
require_relative 'aws_helpers/kms_helper'
require_relative 'aws_helpers/rds_helper'
require_relative 'aws_helpers/route53_helper'
require_relative 'aws_helpers/s3_helper'
require_relative 'aws_helpers/states_helper'
require_relative 'aws_helpers/sts_helper'
require_relative 'aws_helpers/ssm_helper'
require_relative 'aws_helpers/codedeploy_helper'
require_relative 'aws_helpers/amq_broker_helper'
require_relative 'aws_helpers/ecr_helper'
require_relative 'aws_helpers/application_autoscaling_helper'

require "#{BASE_DIR}/lib/service_container"
require "#{BASE_DIR}/lib/services/retryable_service.rb"

# Class extends StandardError and provides attribute for capturing partial outputs on exception
# @attr_reader partial_outputs [Hash] captures partial outputs as part of caught exception
class ActionError < StandardError
  attr_reader :partial_outputs

  def initialize(outputs = {})
    @partial_outputs = outputs
  end
end

# Class is responsible for providing access to AWS SDK wrapper methods
class AwsHelperClass
  include AutoscalingHelper
  include CloudFormationHelper
  include DynamoDbHelper
  include Ec2Helper
  include ElastiCacheHelper
  include IamHelper
  include KinesisHelper
  include LambdaHelper
  include KmsHelper
  include RdsHelper
  include Route53Helper
  include S3Helper
  include StatesHelper
  include StsHelper
  include SsmHelper
  include CodeDeployHelper
  include AmqBrokerHelper
  include EcrHelper
  include ApplicationAutoscalingHelper

  # initialises AwsHelperClass with all service specific mixins
  # @param proxy [String] proxy server to be used for API access
  # @param region [String] AWS region to be used for targeted API endpoint
  # @param control_role [String] control role assumed by the pipeline
  # @param provisioning_role [String] account specific provisioning role assume  by the pipeline
  def initialize(
    proxy: nil,
    region: 'ap-southeast-2',
    control_role: nil,
    provisioning_role: nil,
    s3_role: nil
  )
    @client_mutex = Mutex.new

    @retry_limit = 10

    @proxy = proxy unless proxy.nil?
    @region = region

    Aws.config[:retry_limit] = 10

    _autoscaling_helper_init
    _cloudformation_helper_init
    _dynamodb_helper_init
    _ec2_helper_init
    _elasticache_helper_init
    _iam_helper_init
    _kinesis_helper_init
    _kms_helper_init
    _lambda_helper_init
    _route53_helper_init
    _rds_helper_init
    _s3_helper_init(s3_role)
    _ssm_helper_init
    _codedeploy_helper_init
    _sts_helper_init(control_role: control_role, provisioning_role: provisioning_role)
    _amq_broker_helper_init
    _ecr_helper_init
  end

  # Retry service used by other helpers to implement try-retry over non-retryable methods
  # it's lazy-load, will be initialied at first request to avoid static initializations with mixins
  # @return [RetryableService] an instance of RetryableService class
  def retry_service
    if @retry_service.nil?
      @retry_service = ServiceContainer.instance.get_service(RetryableService)
    end

    @retry_service
  end
end
