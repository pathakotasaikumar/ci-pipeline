module Defaults
  module Environment
    extend self

    #
    # Bamboo plan variables
    # Note: Variables with no set defaults are REQUIRED

    # @return [String] Default value for HTTP proxy
    def proxy
      ENV.fetch('bamboo_agent_proxy', nil)
    end

    # @return [String] Default value for AWS region
    def region
      ENV.fetch('bamboo_aws_region', 'ap-southeast-2')
    end

    def account_id
      ENV.fetch('bamboo_aws_account_id', nil)
    end

    # @return [String] Default value for control role
    def control_role
      ENV.fetch('bamboo_aws_control_role', nil)
    end

    # Set S3 bucket details
    def pipeline_bucket_name
      ENV.fetch('bamboo_pipeline_bucket_name', 'qcp-pipeline')
    end

    # @return [String] Value for context storage type
    def context_storage
      ENV.fetch('context_storage', 'real')
    end

    # @return [String] Value for AWS region
    def plan_key
      ENV['bamboo_custom_planKey'] || ENV['bamboo_planKey']
    end

    # @return [String] Value for Bamboo branch
    def branch
      ENV['bamboo_custom_branchName'] || ENV['bamboo_planRepository_branchName']
    end

    # @return [String] Value for Bamboo build number
    def build
      ENV['bamboo_custom_buildNumber'] || ENV['bamboo_buildNumber']
    end

    # @return [String] Default value for Bamboo deployment environment
    def environment
      ENV['bamboo_deployment_env']
    end

    # @return [String] String value for Bamboo user initiating the build
    def build_user
      ENV['bamboo_ManualBuildTriggerReason_userName']
    end

    def provisioning_role_name
      ENV.fetch('bamboo_aws_provisioning_role_name', 'qcp-platform-provision')
    end

    # @return [String] Default provisioning role ARN based on AWS account and Provisioning Role Name
    def provisioning_role
      return if account_id.nil? || provisioning_role_name.nil?

      "arn:aws:iam::#{account_id}:role/#{provisioning_role_name}"
    end

    def ams_bucket_name
      Context.environment.variable('ams_bucket_name', default_ams_bucket_name)
    end

    def qda_bucket_name
      Context.environment.variable('qda_bucket_name', default_qda_bucket_name)
    end

    def as_bucket_name
      Context.environment.variable('as_bucket_name', default_as_bucket_name)
    end

    # @return [String] The default AMS bucket name (shared between QDAs within an AMS)
    def default_ams_bucket_name
      "qf-#{sections[:ams]}"
    end

    # @return [String] The default QDA bucket name (shared between app services within a QDA)
    def default_qda_bucket_name
      "qf-#{sections[:ams]}-#{sections[:qda]}-#{sections[:env][0]}-00"
    end

    # @return [String] The default application bucket name
    def default_as_bucket_name
      "qf-#{sections[:ams]}-#{sections[:qda]}-#{sections[:env][0]}-#{sections[:as]}"
    end

    # @return [String] The root directory where pipeline code lives
    def pipeline_dir
      # This is derived from where this file current lives
      File.expand_path("../..", __dir__)
    end

    # @return [String] The root directory where both pipeline and app directory lives
    def build_dir
      File.expand_path("..", pipeline_dir)
    end

    def logs_dir
      File.join(build_dir, "logs")
    end
  end
end
