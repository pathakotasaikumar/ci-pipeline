require_relative "pipeline_autoscaling_action_builder"
require_relative "instance_builder"
require_relative "lambda_function_builder"

# Module functions as a proxy for PipelineAutoscalingAction
# Generates autoscaling lifecycle action for handling volume attachment to autoscaling instances
module PlatformSecretManagementBuilder
  include PipelineAutoscalingActionBuilder
  include InstanceBuilder
  include LambdaFunctionBuilder

  # @param template [Hash] reference to CloudFormation template
  # @param autoscaling_group_name [String] unique autoscaling group name
  # @param execution_role_arn [String] arn for the IAM role to be assigned to lambda executor
  # @param notification_role_arn [String] arn for the IAM role to be assigned to autoscaling group for notifications
  # @param notification_attachments [Hash] list of key value pairs of volume ids and device ids to be used for attachment
  def _process_platform_secret_attachments(
    template: nil,
    autoscaling_group_name: nil,
    execution_role_arn: nil,
    notification_role_arn: nil,
    notification_attachments: nil,
    component_name: nil
  )

    _prepare_and_upload_package_to_s3(component_name: component_name)

    _process_pipeline_autoscaling_action(
      template: template,
      action_name: "SecretManagement",
      autoscaling_group_name: autoscaling_group_name,
      execution_role_arn: execution_role_arn,
      notification_role_arn: notification_role_arn,
      notification_metadata: notification_attachments.to_json,
      lambda_code: "platform.zip",
      heartbeat_timeout: 300,
      lifecycle_transition: "autoscaling:EC2_INSTANCE_LAUNCHING",
      handler_name: "platform_secret_management.handler"
    )

    _process_pipeline_autoscaling_action(
      template: template,
      action_name: "SecretManagementTermination",
      autoscaling_group_name: autoscaling_group_name,
      execution_role_arn: execution_role_arn,
      notification_role_arn: notification_role_arn,
      notification_metadata: notification_attachments.to_json,
      lambda_code: "platform.zip",
      heartbeat_timeout: 300,
      lifecycle_transition: "autoscaling:EC2_INSTANCE_TERMINATING",
      handler_name: "platform_secret_management_param_deletion.handler"
    )
  end

  # @param template [Hash] reference to CloudFormation template
  # @param execution_role_arn [String] arn for the IAM role to be assigned to lambda executor
  # @param environment_variables [Hash] list of key value pairs of volume ids and device ids to be used for attachment
  def _process_platform_secret_attachments_for_instance(
    template: nil,
    execution_role_arn: nil,
    environment_variables: nil,
    resource_name: nil,
    component_name: nil
  )

    _prepare_and_upload_package_to_s3(component_name: component_name)

    _process_lambda_function(
      template: template,
      role: execution_role_arn,
      function_definition: {
        "#{resource_name}" => {
          "Properties" => {
            "Handler" => "platform_secret_management.handler",
            "Runtime" => "python3.9",
            "Timeout" => 300,
            "Code" => "platform.zip",
            "Environment" => { 'Variables' => environment_variables }
          }
        }
      }
    )
  end

  # @param component_name [String] name of the owning component
  # @param execution_role_name [String] name of the role to be assigned to lambda executor
  # @return [Array] list of security rules required for the lambda executor and notification roles
  def _platform_secret_attachment_security_rules(
    component_name: nil,
    execution_role_name: nil
  )

    [

      IamSecurityRule.new(
        roles: "#{component_name}.#{execution_role_name}",
        actions: %w(
          s3:GetObject
          s3:GetObjectVersion
        ),
        resources: "#{Context.s3.secret_bucket_arn}/*",
      ),
      IamSecurityRule.new(
        roles: "#{component_name}.#{execution_role_name}",
        actions: %w(
          ssm:PutParameter
        ),
        resources: [_ssm_platform_secret_parameter_arn(component_name: component_name)]
      ),
      IamSecurityRule.new(
        roles: "#{component_name}.#{execution_role_name}",
        actions: [
          'ssm:DeleteParameter',
          'ssm:DeleteParameters',
          'ssm:DescribeParameters',
          'ssm:GetParameter',
          'ssm:GetParameters',
          'ssm:GetParametersByPath'
        ],
        resources: [_ssm_platform_secret_parameter_arn(component_name: component_name)]
      ),
      IamSecurityRule.new(
        roles: "#{component_name}.#{execution_role_name}",
        actions: %w(
          ec2:CreateNetworkInterface
          ec2:DescribeNetworkInterfaces
          ec2:DeleteNetworkInterface
          ec2:DescribeInstances
          ec2:AttachNetworkInterface
          ec2:DetachNetworkInterface
          ec2:ModifyNetworkInterfaceAttribute
          ec2:ResetNetworkInterfaceAttribute
          autoscaling:CompleteLifecycleAction
        ),
        resources: "*"
      ),
      IamSecurityRule.new(
        roles: "#{component_name}.#{execution_role_name}",
        actions: %w(
          logs:CreateLogStream
          logs:PutLogEvents
        ),
        resources: %w(arn:aws:logs:*:*:*)
      ),
      IamSecurityRule.new(
        roles: "#{component_name}.#{execution_role_name}",
        actions: %w(
          kms:Describe*
          kms:Encrypt
          kms:GenerateDataKey
          kms:GenerateDataKeyWithoutPlaintext
          kms:GenerateRandom
          kms:ReEncrypt*
        ),
        resources: Context.kms.secrets_key_arn
      )
    ]
  end

  # @return [Hash] list of key value pairs for volumes ids and device index values for attachment
  def _platform_secrets_metadata
    {
      "Sections" => Defaults.sections.to_json,
      "KmsId" => Context.kms.secrets_key_arn,
      "SecretsStorageBucket" => Defaults.secrets_bucket_name,
      "SecretsStorageFileLocation" => Defaults.secrets_file_location_path,
      "AwsProxy" => Context.environment.variable("aws_proxy", "")
    }
  end

  def _prepare_and_upload_package_to_s3(component_name:)
    artefact_dir = "#{__dir__}/../common/"
    artefact_file_name = File.join "#{artefact_dir}" + 'platform.zip'

    cmd = "cd #{artefact_dir} && zip -r #{artefact_file_name} *.py"

    system("echo 'Checking zip presense'")
    which_zip_result = system('which zip')

    if which_zip_result != 0 && which_zip_result != true
      raise "Cannot find 'zip' command - 'which zip' exit code was: #{which_zip_result}"
    end

    system(cmd)

    _upload_package_artefact(artefact_file_name, component_name)

    FileUtils.rm_f artefact_file_name
  end

  # uploads lambda artefact to s3 for deployment
  # @param artefact_name [String] Artefact file name specified for the lambda function
  def _upload_package_artefact(artefact_name, component_name)
    upload_artefact_bucket = Context.s3.lambda_artefact_bucket_name

    cd_artefact_path = Defaults.cd_artefact_path(component_name: component_name)

    unless File.exist?(artefact_name)
      raise "Unable to locate #{artefact_name}. " \
        "Ensure lambda code is packaged as a single zip artefact"
    end

    begin
      file_name = File.basename(artefact_name)
      Log.debug "Uploading file to #{upload_artefact_bucket}/#{cd_artefact_path}/#{file_name}"
      AwsHelper.s3_upload_file(
        upload_artefact_bucket, "#{cd_artefact_path}/#{file_name}", artefact_name
      )
    rescue => e
      raise "Unable to upload file to #{upload_artefact_bucket}/#{cd_artefact_path}/#{file_name} - #{e}"
    end
  rescue => e
    raise "Unable to unpack and upload lambda artefact #{artefact_name} - #{e}"
  end
end
