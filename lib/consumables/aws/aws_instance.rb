require "consumable"
require "util/user_data"
require "util/obj_to_text"
require "util/tag_helper"
require_relative "builders/instance_builder"
require_relative "builders/instance_profile_builder"
require_relative "builders/route53_record_builder"
require_relative "builders/instance_scheduled_action_builder"
require_relative "builders/pipeline_instance_backup_policy_builder"
require_relative 'builders/dns_record_builder'
require_relative 'builders/platform_secret_management_builder'

# Extends Consumable class single instance component
class AwsInstance < Consumable
  include InstanceBuilder
  include InstanceProfileBuilder
  include Route53RecordBuilder
  include InstanceScheduledActionBuilder
  include PipelineInstanceBackupPolicyBuilder
  include DnsRecordBuilder
  include PlatformSecretManagementBuilder

  def initialize(component_name, definition)
    super(component_name, definition)

    @instance = {}
    @scheduled_actions = {}
    @backup_policy = {}

    # Load resources from the component definition
    (definition["Configuration"] || {}).each do |name, resource|
      type = resource["Type"]

      case type
      when "AWS::EC2::Instance"
        raise "This component does not support multiple #{type} resources" unless @instance.empty?

        @instance[name] = resource
      when "Pipeline::EC2::ScheduledAction"
        @scheduled_actions[name] = resource
      when "Pipeline::Features"
        @features[name] = resource
      when "Pipeline::Instance::BackupPolicy"
        @backup_policy[name] = resource
      when nil
        raise "Must specify a type for resource #{name.inspect}"
      else
        raise "Resource type #{type.inspect} is not supported by this component"
      end
    end

    # Assign default names to unspecified resources
    @instance = { "Instance" => {} } if @instance.empty?

    @instance_name = @instance.keys.first
  end

  # @return (see Consumable#security_items)
  def security_items
    security_items = [
      {
        "Name" => "SecurityGroup",
        "Type" => "SecurityGroup",
        "Component" => @component_name,
      },
      {
        "Name" => "InstanceRole",
        "Type" => "Role",
        "Component" => @component_name,
        "ManagedPolicyArns" => Context.asir.managed_policy_arn_list,
      },
      {
        "Name" => "LambdaSecretManagementExecutionRole",
        "Type" => "Role",
        "Component" => @component_name,
        "Service" => "lambda.amazonaws.com"
      }
    ]

    if @scheduled_actions.any?
      security_items += _ec2_scheduled_action_security_items(
        component_name: @component_name
      )
    end

    security_items
  end

  # Overriding the final security rules update for the component with skip_non_existant to true
  def finalise_security_rules
    _update_security_rules(
      rules: security_rules,
      skip_non_existant: true,
      create_empty: true,
    )
  end

  # @return (see Consumable#security_rules)
  def security_rules
    # Different security rules during bake and deploy
    security_rules = []

    security_rules += _platform_security_rules(destination: "#{@component_name}.SecurityGroup")
    security_rules += _instance_base_security_rules(component_name: @component_name)
    security_rules += _instance_qualys_key_rules(component_name: @component_name)
    security_rules += _instance_legacy_security_rules(component_name: @component_name)
    security_rules += _lri_instance_security_rules(component_name: @component_name)
    security_rules += _instance_deploytime_security_rules(component_name: @component_name)

    security_rules += _parse_security_rules(
      type: :ip,
      rules: @instance.values[0]["Security"],
      destination: "#{@component_name}.SecurityGroup",
    )

    # Lifecycle hook secret management permission
    security_rules += _platform_secret_attachment_security_rules(
      component_name: @component_name,
      execution_role_name: "LambdaSecretManagementExecutionRole"
    )

    if @scheduled_actions.any?
      security_rules += _ec2_scheduled_action_security_rules(
        component_name: @component_name,
        instance_name: @instance_name
      )
    end

    return security_rules
  end

  def deploy
    # Determine SOE details
    soe_alias = JsonTools.get(@instance.values[0], "Properties.ImageId", "@default")
    soe_ami = Defaults.image_by_dns(soe_alias) || Defaults.soe_ami_id(soe_alias)
    soe_ami_details = AwsHelper.ec2_get_image_details(soe_ami)
    soe_ami_id = soe_ami_details[:id]
    soe_tags = soe_ami_details[:tags]
    soe_ami_name = soe_ami_details[:name]
    platform = soe_ami_details[:platform]
    Context.component.set_variables(component_name, { 'operating_system' => platform.to_s })

    if platform == :unknown
      raise "Cannot determine operating system type of image #{soe_ami_id} (ImageName = #{soe_ami_name}, Alias = #{soe_alias})"
    end

    long_lived = false
    long_lived_restore_ami = nil

    @pipeline_features.each do |feature|
      feature_name = feature.name.downcase
      next unless feature_name == 'longlived' and feature.enabled?

      # Get the AMI ID if this is a DR/Restore from backup
      long_lived = true
      long_lived_restore_ami = feature.restore_ami
    end

    _upload_cd_artefacts(
      component_name: @component_name,
      platform: platform,
      soe_ami_id: soe_ami_id,
      objects: {},
      pipeline_features: @pipeline_features
    )

    securityrules = security_rules
    # Create the baketime security rules
    _update_security_rules(rules: securityrules)

    # Deploy instance stack
    Log.info "Creating instance stack"
    stack_name = Defaults.component_stack_name(@component_name)
    tags = Defaults.get_tags(@component_name)

    # Long lived and attempting to restore
    # Check if instances are running and fail if they are
    if long_lived and long_lived_restore_ami

      # Statuses that should stop restoration
      active_states = {
        :pending => 0,
        :running => 16
      }

      # Get name from specified AMI
      Log.debug "Getting image details for Long Lived AMI: #{long_lived_restore_ami}"
      ami_details = AwsHelper.ec2_get_image_details(long_lived_restore_ami)

      # Get the tags from the AMI
      ami_tags = {}
      ami_details[:tags].each do |tag|
        ami_tags[tag.key] = tag.value
      end

      # Check if any instances are running
      instances = AwsHelper.ec2_get_instance_status(ami_tags['Name'])

      instances.each do |instance_state|
        if active_states.values.include? instance_state[:code]
          Log.error "Instance with name #{ami_tags['Name']} is in running or pending state. Aborting Long Running Instance restore!"
          raise "Cannot restore Long Running Instance while existing instance is in 'running' or 'pending' states."
        else
          Log.debug "No instances with name #{ami_tags['Name']} detected. Proceeding..."
        end
      end

      sections = Defaults.sections

      if [
        ami_tags['AMSID'].upcase != sections[:ams].upcase,
        ami_tags['EnterpriseAppID'].upcase != sections[:qda].upcase,
        ami_tags['ApplicationServiceID'].upcase != sections[:as].upcase
      ].any?

        raise "ERROR: The AMI ID #{long_lived_restore_ami} does not belong to "\
           "the current Application Service ID #{sections[:qda].upcase}-#{sections[:as].upcase}"
      else
        Log.debug "Checked ownership of LRI AMI #{long_lived_restore_ami} and OK."
      end
    end

    @pipeline_features.map { |f| tags += f.feature_tags }
    tags += TagHelper.get_tag_values(tags: soe_tags, default_value: soe_ami_name, tag_key: 'SOE_ID')

    # Create the lambda function stack to populate the secrets to SSM
    secret_management_lambda_stack_name = Defaults.component_stack_name("#{@component_name}Lambda")
    secret_management_lambda_template = _prepare_secret_lambda_template(resource_name: "SecretManagementLambda")

    begin
      stack_outputs = {}
      stack_outputs = AwsHelper.cfn_create_stack(
        stack_name: secret_management_lambda_stack_name,
        template: secret_management_lambda_template,
        tags: tags
      )
    rescue ActionError => e
      stack_outputs = e.is_a?(ActionError) ? e.partial_outputs : {}
      raise "Failed to create stack - #{e}"
    ensure
      Context.component.set_variables(@component_name, stack_outputs)
    end

    # Updating InstanceRole permission to provide invoke lambda permission
    securityrules << IamSecurityRule.new(
      roles: "#{@component_name}.InstanceRole",
      actions: %w(
        lambda:InvokeFunction
      ),
      resources: Context.component.variable(
        @component_name,
        "SecretManagementLambdaArn"
      )
    )
    _update_security_rules(rules: securityrules)

    template = _full_template(image_id: soe_ami_id, platform: platform)
    Context.component.set_variables(@component_name, { "Template" => template })

    begin
      stack_outputs = {}
      stack_outputs = AwsHelper.cfn_create_stack(
        stack_name: stack_name,
        template: template,
        tags: tags
      )
    rescue ActionError => e
      stack_outputs = e.is_a?(ActionError) ? e.partial_outputs : {}
      raise "Failed to create instance stack - #{e}"
    ensure
      Context.component.set_variables(@component_name, stack_outputs)

      # Copy all the produced log files to a local log directory
      AwsHelper.s3_download_objects(
        bucket: Context.s3.artefact_bucket_name,
        prefix: Defaults.log_upload_path(component_name: component_name, type: "deploy"),
        local_path: "#{Defaults.logs_dir}/#{@component_name}/deploy",
        validate: false
      )
    end

    # Create deployment DNS names
    return unless Defaults.ad_dns_zone?

    begin
      Log.debug "Deploying AD DNS records"

      dns_name = Defaults.deployment_dns_name(
        component: @component_name,
        zone: Defaults.ad_dns_zone
      )

      endpoint = Context.component.variable(
        @component_name,
        "#{@instance_name}PrivateIp"
      )

      deploy_ad_dns_records(
        dns_name: dns_name,
        endpoint: endpoint,
        type: 'A',
        ttl: '60'
      )
    rescue => error
      Log.error "Failed to deploy DNS records - #{error}"
      raise "Failed to deploy DNS records - #{error}"
    end
  end

  def pre_deploy
    @pipeline_features.each do |feature|
      feature_name = feature.name.downcase
      begin
        case feature_name
        when 'ips'
          feature.activate(:PreDeploy)
        end
      rescue => error
        Log.error "Failed to process pre_deploy task for feature #{feature_name} - #{error}"
      end
    end
  end

  def post_deploy
    @pipeline_features.each do |feature|
      feature_name = feature.name.downcase
      begin
        case feature_name
        when 'qualys', 'ips'
          feature.activate(:PostDeploy)
        end
      rescue => error
        Log.error "Failed to process post_deploy task for feature #{feature_name} - #{error}"
      end
    end
  end

  def post_teardown
    @pipeline_features.each do |feature|
      feature_name = feature.name.downcase
      begin
        case feature_name
        when 'ips'
          feature.activate(:PostTeardown)
        end
      rescue => error
        Log.error "Failed to process post_deploy task for feature #{feature_name} - #{error}"
      end
    end
  end

  # Execute release for the component
  def release
    super
  end

  # Execute teardown for the component stack
  def teardown
    exception = nil

    secretmanagement_lambda_name = Context.component.variable(
      @component_name,
      "SecretManagementLambdaName",
      nil
    )

    secret_management_lambda_stack_name = Defaults.component_stack_name("#{@component_name}Lambda")

    # Teardown component stack
    begin
      stack_id = Context.component.stack_id(@component_name)
      AwsHelper.cfn_delete_stack(stack_id) unless stack_id.nil?
    rescue => e
      exception ||= e
      Log.warn "Failed to delete stack #{stack_id.inspect} during teardown - #{e}"
    end

    # Teardown component lambda component if exist
    begin
      AwsHelper.cfn_delete_stack(secret_management_lambda_stack_name) unless secret_management_lambda_stack_name.nil?
    rescue => e
      Log.warn "Failed to delete stack #{secret_management_lambda_stack_name.inspect}. - #{e}"
    end

    unless secret_management_lambda_stack_name.nil?
      # Clean up the network interfaces used by the Lambda - (QCP-2506, QCP-4014)
      begin
        requester_ids_array = ["*:#{secret_management_lambda_stack_name}"]
        requester_ids_array.push("*:#{secretmanagement_lambda_name}") unless secretmanagement_lambda_name.nil?

        network_interfaces = AwsHelper.ec2_lambda_network_interfaces(
          requester_ids: requester_ids_array
        )

        if network_interfaces.nil? || network_interfaces.empty?
          Log.debug "Skipping cleanup - no network network interfaces found attached to #{@component_name.inspect}"
        else
          Log.info "Network interfaces to delete - #{network_interfaces}"
          Log.debug "Removing network interfaces attached to #{requester_ids_array}"
          AwsHelper.ec2_delete_network_interfaces(network_interfaces)
        end
      rescue => e
        Log.warn "Failed to clean up network interfaces for #{@component_name.inspect} during teardown - #{e}"
      end
    end

    # Clean up deployment DNS records
    begin
      _clean_ad_deployment_dns_record(@component_name)
      _clean_ad_release_dns_record(@component_name)
    rescue => e
      exception ||= e
      Log.warn "Failed to remove AD DNS records during teardown - #{e}"
    end

    raise exception unless exception.nil?
  end

  def default_pipeline_features
    super.merge(
      {
        "CodeDeploy" => "disabled",
        "IPS" => {
          "Enabled" => "true",
          "Behaviour" => "detective"
        }
      }
    )
  end

  private

  def _prepare_secret_lambda_template(resource_name: nil)
    template = { "Resources" => {}, "Outputs" => {} }

    _process_platform_secret_attachments_for_instance(
      template: template,
      execution_role_arn: Context.component.role_arn(@component_name, "LambdaSecretManagementExecutionRole"),
      environment_variables: _platform_secrets_metadata,
      resource_name: resource_name,
      component_name: @component_name,
    )

    return template
  end

  # @param (see AwsAutoscale#_full_template)
  def _full_template(
    image_id: nil,
    platform: nil
  )
    template = { "Resources" => {}, "Outputs" => {} }

    # Generate instance profile
    _process_instance_profile(
      template: template,
      instance_role_name: Context.component.role_name(@component_name, "InstanceRole")
    )

    windows_ou = _resolve_default_ou_path(
      current_value: JsonTools.get(@instance.values.first,
                                   "Properties.Pipeline::WindowsOUPath",
                                   "@default"),
      ams: Defaults.sections[:ams],
      qda: Defaults.sections[:qda],
      as: Defaults.sections[:as],
      env: Defaults.sections[:env]
    )

    # Generate Instance to bake
    user_data_variables = {
      "AwsProxy" => Context.environment.variable("aws_proxy", ""),
      "DeploymentEnv" => Defaults.sections[:env] == "prod" ? "Production" : "NonProduction",
      "Domain" => Defaults.ad_join_domain,
      "MetadataResource" => @instance_name,
      "NoProxy" => Context.environment.variable("aws_no_proxy", ""),
      "Region" => { "Ref" => "AWS::Region" },
      "RemoteLogsPath" => "#{Context.s3.artefact_bucket_name}/#{Defaults.log_upload_path(component_name: component_name, type: "deploy")}",
      "ResourceToSignal" => @instance_name,
      "StackId" => { "Ref" => "AWS::StackId" },
      "WindowsOU" => windows_ou,
      "TrenddsmUrl" => Defaults.trend_dsm_url,
      "TrendPolicyName" => Defaults.component_name_tag(component_name: component_name),
      "AwsCliSource" => Context.environment.variable('aws_cli_source', ''),
      "AwsCfnSource" => Context.environment.variable('aws_cfn_source', ''),
      "AwsCfnSourcepy" => Context.environment.variable('aws_cfn_source_py', ''),
      "SecretManagementLambdaArn" => Context.component.variable(@component_name, "SecretManagementLambdaArn", ''),
      "SSMPlatformVariablePath" => _ssm_platform_secret_path
    }

    # Build metadata for instance deployment
    bucket_name = Context.s3.artefact_bucket_name
    artefact_path = Defaults.cd_artefact_path(component_name: component_name)

    # Build the Metadata for the stack - Regular or Long Lived
    metadata = {}
    long_lived = false
    long_lived_restore_ami = nil
    puppet_server = nil
    puppet_environment = nil
    puppet_development = nil

    @pipeline_features.each do |feature|
      feature_name = feature.name.downcase
      next unless feature_name == 'longlived' and feature.enabled?

      # Get the AMI ID if this is a DR/Restore from backup
      long_lived = true
      long_lived_restore_ami = feature.restore_ami
      puppet_server = feature.puppet_server
      puppet_environment = feature.puppet_environment
      puppet_development = feature.puppet_development
    end

    case platform
    when :amazon_linux, :rhel, :centos, :linux
      if long_lived and long_lived_restore_ami
        user_data = UserData.load_aws_userdata(
          "#{__dir__}/aws_instance/lri-linux-restore.sh",
          user_data_variables
        )
      else
        user_data = UserData.load_aws_userdata(
          "#{__dir__}/aws_instance/linux-deploy.sh",
          user_data_variables
        )
      end

    when :windows
      if long_lived and long_lived_restore_ami
        user_data = UserData.load_aws_userdata(
          "#{__dir__}/aws_instance/lri-windows-restore.ps1",
          user_data_variables
        )
      else
        user_data = UserData.load_aws_userdata(
          "#{__dir__}/aws_instance/windows-deploy.ps1",
          user_data_variables
        )
      end
    end

    if long_lived == true
      if long_lived_restore_ami
        # Blow away metadata if we're restoring
        metadata = [_metadata_auth(@component_name, bucket_name)].inject(&:merge)
      else
        Log.debug "The Instance is using the long lived feature and will be configured with #{puppet_server}, #{puppet_environment}, #{puppet_development}"

        # Long Running (LRI) Instance Metadata
        metadata = [
          _metadata_pre_prepare(platform, bucket_name, artefact_path),
          _metadata_pre_deploy(platform),
          _metadata_post_deploy_lri(platform, puppet_server, puppet_environment, puppet_development),
          _metadata_auth(@component_name, bucket_name)
        ].inject(&:merge)
      end
    else
      # Non-LRI Regular Instance Metadata

      Log.debug "The Instance is not using the long lived feature"

      metadata = [
        _metadata_pre_prepare(platform, bucket_name, artefact_path),
        _metadata_pre_deploy(platform),
        _metadata_post_deploy(platform),
        _metadata_auth(@component_name, bucket_name)
      ].inject(&:merge)
    end

    security_group_ids = [
      Context.component.sg_id(@component_name, "SecurityGroup"),
      Context.asir.source_sg_id
    ]
    security_group_ids << Context.asir.destination_sg_id if ingress?

    # We check whether this is a long_lived restore otherwise use the image_id that's been specified
    _process_instance(
      template: template,
      instance_definition: @instance,
      user_data: user_data,
      security_group_ids: security_group_ids,
      instance_profile: { "Ref" => "InstanceProfile" },
      shutdown_behaviour: "stop",
      image_id: (long_lived && long_lived_restore_ami) ? long_lived_restore_ami : image_id,
      metadata: metadata
    )

    _add_recovery_alarm(
      template: template,
      instance: @instance_name
    )

    scheduled_action_definitions = _parse_ec2_scheduled_actions(
      definitions: @scheduled_actions,
      instance_name: @instance_name
    )

    if @scheduled_actions.any?

      scheduled_action_execution_role = Context.component.role_arn(
        @component_name,
        "Ec2ScheduledActionExecutionRole"
      )

      _process_ec2_scheduled_actions(
        template: template,
        scheduled_actions: scheduled_action_definitions,
        execution_role_arn: scheduled_action_execution_role
      )
    end

    if @backup_policy.any?

      policy_definitions = _parse_instance_backup_policy(
        resource_id: { 'Ref' => @instance_name },
        definitions: @backup_policy,
        component_name: @component_name
      )

      _process_backup_policy(
        template: template,
        backup_policy: policy_definitions
      )

    end

    unless Defaults.ad_dns_zone?
      _process_deploy_r53_dns_records(
        template: template,
        component_name: @component_name,
        zone: Defaults.r53_hosted_zone,
        resource_records: [{ 'Fn::GetAtt' => [@instance_name, 'PrivateIp'] }],
        ttl: '60',
        type: 'A'
      )
    end

    return template
  end
end