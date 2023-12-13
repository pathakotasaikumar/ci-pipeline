require "consumable"
require "util/user_data"
require "util/obj_to_text"
require "util/tag_helper"

require_relative "builders/alarm_builder"
require_relative "builders/autoscaling_group_builder"
require_relative "builders/autoscaling_volume_tag_builder"
require_relative "builders/instance_builder"
require_relative "builders/instance_profile_builder"
require_relative "builders/launch_configuration_builder"
require_relative "builders/lifecycle_hook_builder"
require_relative "builders/load_balancer_builder"
require_relative "builders/network_attachment_builder"
require_relative "builders/route53_record_builder"
require_relative "builders/scheduled_action_builder"
require_relative "builders/volume_attachment_builder"
require_relative "builders/wait_condition_builder"
require_relative "builders/pipeline_instance_backup_policy_builder"
require_relative "builders/dns_record_builder"
require_relative "builders/platform_secret_management_builder"

# Extends Consumable class
# Builds aws/autoheal pipeline component
# @attr_reader autoscaling_group [Hash] definition for AWS::AutoScaling::AutoscalingGroup resource
class AwsAutoheal < Consumable
  include AlarmBuilder
  include AutoscalingGroupBuilder
  include AutoscalingVolumeTagBuilder
  include InstanceBuilder
  include InstanceProfileBuilder
  include LaunchConfigurationBuilder
  include LifecycleHookBuilder
  include LoadBalancerBuilder
  include NetworkAttachmentBuilder
  include Route53RecordBuilder
  include ScheduledActionBuilder
  include VolumeAttachmentBuilder
  include PipelineInstanceBackupPolicyBuilder
  include DnsRecordBuilder
  include PlatformSecretManagementBuilder

  attr_reader :autoscaling_group

  # @param (see Consumable#initialize)
  def initialize(component_name, definition)
    super(component_name, definition)

    @bake_instance = {}
    @backup_policy = {}
    @load_balancer = {}
    @autoscaling_group = {}
    @launch_configuration = {}
    @launch_template = {}
    @lifecycle_hooks = {}
    @scheduled_actions = {}
    @volume_attachments = {}
    @network_attachments = {}
    @alarms = {}

    # Load resources from the component definition
    (definition["Configuration"] || {}).each do |name, resource|
      type = resource["Type"]

      case type
      when "AWS::EC2::Instance"
        raise "This component does not support multiple #{type} resources" unless @bake_instance.empty?

        @bake_instance[name] = resource
      when "AWS::ElasticLoadBalancing::LoadBalancer"
        raise "This component does not support multiple #{type} resources" unless @load_balancer.empty?

        @load_balancer[name] = resource
      when "AWS::AutoScaling::LaunchConfiguration"
        raise "This component does not support multiple #{type} resources" unless @launch_configuration.empty?

        @launch_configuration[name] = resource
      when "AWS::AutoScaling::LifecycleHook"
        @lifecycle_hooks["#{name}CustomHook"] = resource
      when "AWS::AutoScaling::AutoScalingGroup"
        raise "This component does not support multiple #{type} resources" unless @autoscaling_group.empty?

        @autoscaling_group[name] = resource
      when "AWS::AutoScaling::ScheduledAction"
        @scheduled_actions[name] = resource
      when "AWS::CloudWatch::Alarm"
        @alarms[name] = resource
      when "Pipeline::Autoheal::VolumeAttachment"
        @volume_attachments[name] = resource
      when "Pipeline::Autoheal::NetworkInterfaceAttachment"
        @network_attachments[name] = resource
      when "Pipeline::Instance::BackupPolicy"
        @backup_policy[name] = resource
      when "Pipeline::Features"
        @features[name] = resource
      when nil
        raise "Must specify a type for resource #{name.inspect}"
      else
        raise "Resource type #{type.inspect} is not supported by this component"
      end
    end

    # Assign default names to unspecified resources
    @launch_configuration = { "LaunchConfiguration" => {} } if @launch_configuration.empty?
    @autoscaling_group = { "AutoScalingGroup" => {} } if @autoscaling_group.empty?

    @bake_instance_name = @bake_instance.keys[0]
    @load_balancer_name = @load_balancer.keys[0]
    @launch_configuration_name = @launch_configuration.keys[0]
    @launch_template_name = @launch_template.keys[0]
    @autoscaling_group_name = @autoscaling_group.keys[0]

    mixedinstance_policy = JsonTools.get(@autoscaling_group.values[0], "Properties.MixedInstancesPolicy", nil)
    if !mixedinstance_policy.nil?
      raise "MixedInstancesPolicy is not supported for aws/autoheal component"
    end

    # Check if values other than 0 or 1 were specified for launch configuration
    capacity_properties = [
      JsonTools.get(@autoscaling_group.values[0], "Properties.MinSize", nil).to_s,
      JsonTools.get(@autoscaling_group.values[0], "Properties.MaxSize", nil).to_s,
      JsonTools.get(@autoscaling_group.values[0], "Properties.DesiredCapacity", nil).to_s,
    ]

    unless (capacity_properties.select { |p| ["0", "1", ""].include? p }).size == capacity_properties.size
      raise "aws/autoheal component only supports '0' and '1' for MinSize, MaxSize and DesiredCapacity properties"
    end
  end

  # @return (see Consumable#security_items)
  def security_items
    security_items = [
      {
        "Name" => "ElbSecurityGroup",
        "Type" => "SecurityGroup",
        "Component" => @component_name
      },
      {
        "Name" => "AsgSecurityGroup",
        "Type" => "SecurityGroup",
        "Component" => @component_name
      },
      {
        "Name" => "InstanceRole",
        "Type" => "Role",
        "Component" => @component_name,
        "ManagedPolicyArns" => Context.asir.managed_policy_arn_list
      },
      {
        "Name" => "LambdaExecutionRole",
        "Type" => "Role",
        "Component" => @component_name,
        "Service" => "lambda.amazonaws.com"
      },
      {
        "Name" => "AutoscalingNotificationRole",
        "Type" => "Role",
        "Component" => @component_name,
        "Service" => "autoscaling.amazonaws.com"
      },
      {
        "Name" => "LambdaSecretManagementExecutionRole",
        "Type" => "Role",
        "Component" => @component_name,
        "Service" => "lambda.amazonaws.com"
      }
    ]

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

    security_rules += _instance_base_security_rules(component_name: @component_name)
    security_rules += _instance_qualys_key_rules(component_name: @component_name)
    security_rules += _platform_security_rules(destination: "#{@component_name}.AsgSecurityGroup")

    if Context.component.variable(@component_name, "ImageId", nil).nil?
      # Still creating the image - must be during bake
      security_rules += _instance_baketime_security_rules(component_name: @component_name)
    else
      # Bake is finished, but still creating the ASG - must be during deploy
      security_rules += _instance_deploytime_security_rules(component_name: @component_name)
    end

    # Allow the ELB to talk to ASG instances on all ports
    security_rules << IpSecurityRule.new(
      sources: "#{@component_name}.ElbSecurityGroup",
      destination: "#{@component_name}.AsgSecurityGroup",
      ports: ["TCP:*"],
    )

    # Load balancer security rules
    if @load_balancer.any?
      security_rules += _parse_security_rules(
        type: :ip,
        rules: @load_balancer.values.first["Security"],
        destination: "#{@component_name}.ElbSecurityGroup",
        mappings: {
          "@listeners" => _get_elb_ports,
        }
      )
    end

    # ASG security rules
    security_rules += _parse_security_rules(
      type: :ip,
      rules: @autoscaling_group.values.first["Security"],
      destination: "#{@component_name}.AsgSecurityGroup"
    )

    # Lifecycle hook notification permissions
    security_rules << IamSecurityRule.new(
      roles: "#{@component_name}.AutoscalingNotificationRole",
      actions: %w(
        sns:Publish
        sqs:GetQueueUrl
        sqs:SendMessage
      ),
      resources: "*"
    )

    # Lifecycle hook permissions for Lambda + Instance
    security_rules << IamSecurityRule.new(
      roles: %W(
        #{@component_name}.LambdaExecutionRole
        #{@component_name}.InstanceRole
      ),
      actions: %w(
        autoscaling:CompleteLifecycleAction
        autoscaling:RecordLifecycleActionHeartbeat
      ),
      resources: '*'
    )

    # Tagging permissions for Lambda volume tagger
    security_rules += _volume_tagger_security_rules(
      component_name: @component_name,
      execution_role_name: "LambdaExecutionRole"
    )

    # Volume attachment permissions
    if @volume_attachments.any?
      security_rules += _volume_attachment_security_rules(
        volume_attachments: @volume_attachments,
        execution_role_name: "LambdaExecutionRole",
        component_name: @component_name
      )
    end

    # Network interface attachment permissions
    if @network_attachments.any?
      security_rules += _network_attachment_security_rules(
        component_name: @component_name,
        execution_role_name: "LambdaExecutionRole"
      )
    end

    # Lifecycle hook secret management permission
    security_rules += _platform_secret_attachment_security_rules(
      component_name: @component_name,
      execution_role_name: "LambdaSecretManagementExecutionRole"
    )

    # Instance permission to change schedule on ASG
    security_rules << IamSecurityRule.new(
      roles: %W(
        #{@component_name}.InstanceRole
      ),
      actions: %w(
        autoscaling:PutScheduledUpdateGroupAction
        autoscaling:SetInstanceProtection
        autoscaling:SuspendProcesses
        autoscaling:ResumeProcesses
      ),
      resources: '*',
      condition: {
        "StringLike" => {
          "autoscaling:ResourceTag/Name" => Defaults.branch_specific_id("*").join("-")
        }
      }
    )
    return security_rules
  end

  # Run deploy actions
  def deploy
    # Determine if a Bake instance was specified
    if @bake_instance.any?
      soe_alias = JsonTools.get(@bake_instance.values.first, "Properties.ImageId", "@default")
      soe_ami = Defaults.image_by_dns(soe_alias) || Defaults.soe_ami_id(soe_alias)
      soe_ami_details = AwsHelper.ec2_get_image_details(soe_ami)
      soe_tags = soe_ami_details[:tags]
      soe_ami_id = soe_ami_details[:id]
      soe_ami_name = soe_ami_details[:name]
      platform = soe_ami_details[:platform]

      raise "Cannot determine operating system type of image #{soe_ami_id}" \
        "(ImageName = #{soe_ami_name}, Alias = #{soe_alias})" if platform == :unknown

      _upload_cd_artefacts(
        component_name: @component_name,
        platform: platform,
        soe_ami_id: soe_ami_id,
        objects: {},
        pipeline_features: @pipeline_features
      )

      # Create the baketime security rules
      _update_security_rules(rules: security_rules)

      # Create the bake instance
      _build_bake_stack(
        soe_ami_id: soe_ami_id,
        soe_ami_name: soe_ami_name,
        soe_tags: soe_tags,
        platform: platform,
      )

      # Create an image from our bake instance
      image_name = Defaults.image_name(soe_ami_name, @component_name)
      tags = Defaults.get_tags(@component_name)
      @pipeline_features.map { |f| tags += f.feature_tags }
      tags += TagHelper.get_tag_values(tags: soe_tags, default_value: soe_ami_name, tag_key: 'SOE_ID')

      create_image_outputs = AwsHelper.ec2_shutdown_instance_and_create_image(
        Context.component.variable(@component_name, "#{@bake_instance_name}Id"),
        image_name,
        tags
      )
      Context.component.set_variables(
        @component_name,
        "ImageId" => create_image_outputs["ImageId"],
        "ImageName" => create_image_outputs["ImageName"]
      )
    else
      # no bake instance detected. Validate LaunchConfiguration Properties.ImageId
      soe_alias = JsonTools.get(@launch_configuration.values.first, "Properties.ImageId", nil)
      soe_ami = if soe_alias =~ /@[\w-]+.[\w-]+/
                  Context.component.replace_variables(soe_alias)
                else
                  Defaults.image_by_dns(soe_alias)
                end

      raise "No BakeInstance resource or ImageId specified in LaunchConfiguration resource" if soe_ami.nil?

      soe_ami_details = AwsHelper.ec2_get_image_details(soe_ami)
      soe_tags = soe_ami_details[:tags]
      soe_ami_name = soe_ami_details[:name]

      # Upload artefacts in deploy time
      _upload_cd_artefacts(
        component_name: @component_name,
        platform: soe_ami_details[:platform],
        soe_ami_id: soe_ami_details[:id],
        pipeline_features: @pipeline_features
      )
      tags = Defaults.get_tags(@component_name)
      @pipeline_features.map { |f| tags += f.feature_tags }
      tags += TagHelper.get_tag_values(tags: soe_tags, default_value: soe_ami_name, tag_key: 'SOE_ID')

      snapshot_copy = JsonTools.get(@launch_configuration.values.first, "Properties.Pipeline::CopySourceImage", true)
      if snapshot_copy.to_s == 'true'
        # Make a copy of the image specified in Launch Configuration
        outputs = AwsHelper.ec2_copy_image(
          source_image_id: soe_ami_details[:id],
          name: Defaults.image_name(soe_ami_details[:name], @component_name),
          tags: tags
        )
      else
        Log.info "Pipeline::CopySourceImage has been set as #{snapshot_copy.inspect}, continuing the deployment without copying the source image."
        outputs = {
          "ImageName" => Defaults.image_name(soe_ami_details[:name], @component_name),
          "ImageId" => soe_ami_details[:id],
        }
      end

      # Add {ImageId => ami-123456, ImageName => ABCD to context vars}
      Context.component.set_variables(@component_name, outputs)
    end

    # Update the security rules
    _update_security_rules(rules: security_rules)

    # Create full autoscaling stack
    _build_full_stack(platform: soe_ami_details[:platform], soe_tags: soe_tags, soe_ami_name: soe_ami_name)

    # Create DNS name for this component
    return unless Defaults.ad_dns_zone? && @load_balancer.any?

    begin
      Log.debug "Deploying AD DNS records"

      dns_name = Defaults.deployment_dns_name(
        component: @component_name,
        zone: Defaults.ad_dns_zone
      )

      endpoint = Context.component.variable(
        @component_name,
        "#{@load_balancer_name}DNSName"
      )

      deploy_ad_dns_records(
        dns_name: dns_name,
        endpoint: endpoint,
        type: 'CNAME',
        ttl: '60'
      )
    rescue => error
      Log.error "Failed to deploy DNS records - #{error}"
      raise "Failed to deploy DNS records - #{error}"
    end
  end

  # Run release action for the component
  def release
    super
  end

  # Run teardown action for the component
  def teardown
    exception = nil

    # Scale down the ASG before teardown to give terminating lifecycle hooks a chance to fire
    begin
      autoscaling_group_name = Context.component.variable(
        @component_name,
        "#{@autoscaling_group_name}Name",
        nil
      )

      if autoscaling_group_name.nil?
        Log.debug "#{@component_name.inspect} ASG resource #{@autoscaling_group_name}" \
                  " was not recorded, cannot scale down to size 0 before teardown"
      else
        Log.debug "Scaling down ASG #{@autoscaling_group_name.inspect} to size 0 before teardown"
        AwsHelper.autoscaling_set_capacity(
          autoscaling_group_name: autoscaling_group_name,
          min_size: 0,
          max_size: 0
        )

        # Wait for scaledown to complete (max 30 minutes)
        Log.debug "Waiting for #{@component_name.inspect} ASG #{@autoscaling_group_name.inspect} to scale down before teardown"
        AwsHelper.autoscaling_wait_for_capacity(
          autoscaling_group_name: autoscaling_group_name,
          min_size: 0,
          max_size: 0,
          delay: 30,
          max_attempts: 60
        )
      end

      # Clean up the network interfaces used by the Lambda - (QCP-2281)
      AwsHelper.clean_up_networkinterfaces(
        component_name: @component_name,
        autoscaling_group_name: autoscaling_group_name
      )
    rescue => e
      Log.warn "Failed to scale down #{@component_name.inspect} ASG #{@autoscaling_group_name.inspect} before teardown - #{e}"
    end

    # Delete the component stack
    begin
      stack_id = Context.component.variable(@component_name, "StackId", nil)
      AwsHelper.cfn_delete_stack(stack_id) unless stack_id.nil?
    rescue => e
      exception ||= e
      Log.warn "Failed to delete component #{@component_name.inspect} stack #{stack_id.inspect} during teardown - #{e}"
    end

    # Deregister AMI and delete instance snapshot
    snapshot_copy = JsonTools.get(@launch_configuration.values.first, "Properties.Pipeline::CopySourceImage", true)
    if snapshot_copy.to_s == 'true'
      begin
        ami_id = Context.component.variable(@component_name, "ImageId", nil)
        AwsHelper.ec2_delete_image(ami_id) unless ami_id.nil?
      rescue => e
        exception ||= e
        Log.warn "Failed to delete AMI #{ami_id.inspect} during teardown - #{e}"
      end
    else
      Log.info "Pipeline::CopySourceImage has been set as #{snapshot_copy.inspect}, continuing the teardown without de-registering the source image."
    end

    begin
      _clean_ad_deployment_dns_record(@component_name)
      _clean_ad_release_dns_record(@component_name)
    rescue => e
      exception ||= e
      Log.warn "Failed to remove AD DNS records during teardown - #{e}"
    end

    raise exception unless exception.nil?
  end

  # @return [Hash] Deploy and Release DNS records for the component
  def name_records
    name_records = custom_name_records(component_name: @component_name, content: @load_balancer, pattern: '@wildcard-qcpaws')

    raise 'Name records must be an Hash.' unless name_records.is_a?(Hash)

    return name_records
  end

  def default_pipeline_features
    super.merge(
      {
        "IPS" => {
          "Enabled" => "true",
          "Behaviour" => "detective"
        }
      }
    )
  end

  # Run Pre Deploy tasks
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

  # Run Post Deploy tasks
  def post_deploy
    @pipeline_features.each do |feature|
      feature_name = feature.name.downcase
      begin
        case feature_name
        when 'qualys', 'ips'
          feature.activate(:PostDeploy) unless capacity_zero?
        end
      rescue => error
        Log.error "Failed to process post_deploy task for feature #{feature_name} - #{error}"
      end
    end
  end

  # Run Post Teardown tasks
  def post_teardown
    @pipeline_features.each do |feature|
      feature_name = feature.name.downcase
      begin
        case feature_name
        when 'ips'
          feature.activate(:PostTeardown) unless capacity_zero?
        end
      rescue => error
        Log.error "Failed to process post_deploy task for feature #{feature_name} - #{error}"
      end
    end
  end

  private

  def capacity_zero?
    min_size = JsonTools.get(@autoscaling_group.values.first, "Properties.MinSize", nil)
    max_size = JsonTools.get(@autoscaling_group.values.first, "Properties.MaxSize", nil)
    return true if min_size <= 0 && max_size <= 0

    return false
  end

  # @return [Array] list of TCP ports used for ELB
  def _get_elb_ports
    elb_ports = []
    if @load_balancer.any?
      listeners = (@load_balancer.values[0]["Properties"] || {})["Listeners"] || []
      elb_ports = listeners.map { |listener|
        next "TCP:#{listener["LoadBalancerPort"]}" if listener.has_key? "LoadBalancerPort"

        next
      }
    end

    return elb_ports
  end

  # Update template with AWS::EC2::Instance resource to be used for baking
  # @param soe_ami_id [String] AMI id to be used for baking instance
  # @param soe_ami_name [String] AMI Name to be used for baking instance
  # @param platform [Symbol] Operating system platform
  def _build_bake_stack(soe_ami_id: nil, soe_ami_name: nil, platform: nil, soe_tags: nil)
    Log.info "Creating bake instance from SOE AMI #{soe_ami_id} (#{soe_ami_name})"
    stack_name = Defaults.component_stack_name(@component_name)

    tags = Defaults.get_tags(@component_name)

    @pipeline_features.map { |f| tags += f.feature_tags }
    tags += TagHelper.get_tag_values(tags: soe_tags, default_value: soe_ami_name, tag_key: 'SOE_ID')

    template = _bake_instance_template(
      image_id: soe_ami_id,
      platform: platform
    )
    Context.component.set_variables(@component_name, { "BakeTemplate" => template })

    begin
      stack_outputs = {}
      stack_outputs = AwsHelper.cfn_create_stack(stack_name: stack_name, template: template, tags: tags)
    rescue ActionError => e
      stack_outputs = e.partial_outputs
      raise "Failed to create instance bake stack - #{e}"
    ensure
      Context.component.set_variables(@component_name, stack_outputs)

      # Copy all the produced log files to a local log directory
      AwsHelper.s3_download_objects(
        bucket: Context.s3.artefact_bucket_name,
        prefix: Defaults.log_upload_path(
          component_name: component_name,
          type: "bake"
        ),
        local_path: "#{Defaults.logs_dir}/#{@component_name}/bake",
        validate: false
      )
    end
  end

  # Updates template with all resources required for the component
  # @param platform [Symbol] Operating system platform
  def _build_full_stack(platform: nil, soe_tags: nil, soe_ami_name: nil)
    Log.info "Creating autoheal consumable resources"

    template = _full_template(
      platform: platform,
      image_id: Context.component.variable(@component_name, "ImageId")
    )
    Context.component.set_variables(@component_name, { "FullTemplate" => template })

    stack_outputs = {}

    begin
      if @bake_instance.any?
        Log.debug "Updating full stack after bake instance"
        stack_outputs = AwsHelper.cfn_update_stack(
          stack_name: Context.component.stack_id(@component_name),
          template: template
        )
      else
        tags = Defaults.get_tags(@component_name)

        @pipeline_features.map { |f| tags += f.feature_tags }
        tags += TagHelper.get_tag_values(tags: soe_tags, default_value: soe_ami_name, tag_key: 'SOE_ID')

        Log.debug "No bake instance specific, building full stack"
        stack_outputs = AwsHelper.cfn_create_stack(
          stack_name: Defaults.component_stack_name(@component_name),
          template: template,
          tags: tags
        )
      end
    rescue ActionError => e
      stack_outputs = e.partial_outputs
      raise "Failed to update full stack - #{e}"
    ensure
      Context.component.set_variables(@component_name, stack_outputs)
    end

    # Update AutoScalingGroup, this time with blank = false so instances get created
    wait_condition = "Wait#{Time.now.strftime('%s')}"

    _process_autoscaling_group(
      template: template,
      platform: platform,
      autoscaling_group_definition: @autoscaling_group,
      load_balancer_name: @load_balancer_name,
      launch_configuration_name: @launch_configuration_name,
      launch_template_name: @launch_template_name,
      wait_condition_name: wait_condition
    )

    begin
      stack_outputs = AwsHelper.cfn_update_stack(
        stack_name: Context.component.stack_id(@component_name),
        template: template
      )
      Log.debug "Successfully updated #{@component_name}"
    rescue => e
      Log.debug "Failed to update #{@component_name}"
      raise "Unable to update #{@component_name} - #{e}"
    ensure
      Context.component.set_variables(@component_name, stack_outputs)
      # Copy all the produced log files to a local log directory
      AwsHelper.s3_download_objects(
        bucket: Context.s3.artefact_bucket_name,
        prefix: Defaults.log_upload_path(
          component_name: component_name,
          type: "deploy/#{wait_condition}"
        ),
        local_path: "#{Defaults.logs_dir}/#{@component_name}/deploy",
        validate: false
      )
    end
  end

  # Generates baking instance template with all resources required for the component
  # @param image_id [String] AMI ID to be used EC2 Instance resource (Baking)
  # @param platform [Symbol] Operating system platform
  def _bake_instance_template(
    image_id: nil,
    platform: nil
  )
    template = { "Resources" => {}, "Outputs" => {} }

    # Generate instance profile
    _process_instance_profile(
      template: template,
      instance_role_name: Context.component.role_name(@component_name, "InstanceRole"),
    )

    windows_ou = _resolve_default_ou_path(
      current_value: JsonTools.get(@bake_instance.values[0],
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
      "DeploymentEnv" => (Defaults.sections[:env] == "prod") ? "Production" : "NonProduction",
      "Domain" => Defaults.ad_join_domain,
      "MetadataResource" => @bake_instance_name,
      "NoProxy" => Context.environment.variable("aws_no_proxy", ""),
      "Region" => { "Ref" => "AWS::Region" },
      "RemoteLogsPath" => "#{Context.s3.artefact_bucket_name}/#{Defaults.log_upload_path(component_name: component_name, type: "bake")}",
      "ResourceToSignal" => @bake_instance_name,
      "StackId" => { "Ref" => "AWS::StackId" },
      "WindowsOU" => windows_ou,
      "AwsCliSource" => Context.environment.variable('aws_cli_source', ''),
      "AwsCfnSource" => Context.environment.variable('aws_cfn_source', ''),
      "AwsCfnSourcepy" => Context.environment.variable('aws_cfn_source_py', '')
    }

    case platform
    when :amazon_linux, :rhel, :centos
      user_data = UserData.load_aws_userdata("#{__dir__}/aws_autoscale/linux-bake.sh", user_data_variables)
    when :windows
      user_data = UserData.load_aws_userdata("#{__dir__}/aws_autoscale/windows-bake.ps1", user_data_variables)
    end

    # Build metadata hash
    bucket_name = Context.s3.artefact_bucket_name
    artefact_path = Defaults.cd_artefact_path(component_name: component_name)

    metadata = [
      _metadata_pre_prepare(platform, bucket_name, artefact_path),
      _metadata_bake_post_deploy(platform),
      _metadata_auth(@component_name, bucket_name)
    ].inject(&:merge)

    bake_security_groups = [
      Context.component.sg_id(@component_name, "AsgSecurityGroup"),
      Context.asir.source_sg_id
    ]

    _process_instance(
      template: template,
      instance_definition: @bake_instance,
      user_data: user_data,
      security_group_ids: bake_security_groups,
      image_id: image_id,
      instance_profile: { "Ref" => "InstanceProfile" },
      default_instance_type: JsonTools.get(@launch_configuration.values[0], "Properties.InstanceType", "m3.medium"),
      shutdown_behaviour: "stop",
      metadata: metadata
    )

    return template
  end

  # Updates template with all resources required for the component
  # @param image_id [String] AMI ID to be used in LaunchConfiguration resource
  # @param platform [Symbol] Operating system platform
  def _full_template(
    image_id: nil,
    platform: nil
  )

    template = { "Resources" => {}, "Outputs" => {} }

    # Generate instance profile
    _process_instance_profile(
      template: template,
      instance_role_name: Context.component.role_name(@component_name, "InstanceRole"),
    )

    # Generate LoadBalancer
    if @load_balancer.any?
      lb_security_groups = [Context.component.sg_id(@component_name, "ElbSecurityGroup")]
      lb_security_groups << Context.asir.destination_sg_id if ingress?
      _process_load_balancer(
        template: template,
        load_balancer_definition: @load_balancer,
        security_group_ids: lb_security_groups,
      )
    end

    windows_ou = _resolve_default_ou_path(
      current_value: JsonTools.get(@launch_configuration.values.first,
                                   "Properties.Pipeline::WindowsOUPath",
                                   "@default"),
      ams: Defaults.sections[:ams],
      qda: Defaults.sections[:qda],
      as: Defaults.sections[:as],
      env: Defaults.sections[:env]
    )

    # Generate LaunchConfiguration
    user_data_variables = {
      "AwsProxy" => Context.environment.variable("aws_proxy", ""),
      "DeploymentEnv" => Defaults.sections[:env] == "prod" ? "Production" : "NonProduction",
      "Domain" => Defaults.ad_join_domain,
      "MetadataResource" => @launch_configuration_name,
      "NoProxy" => Context.environment.variable("aws_no_proxy", ""),
      "Region" => { "Ref" => "AWS::Region" },
      "RemoteLogsPath" => "#{Context.s3.artefact_bucket_name}/#{Defaults.log_upload_path(component_name: component_name, type: "deploy")}",
      "ResourceToSignal" => @autoscaling_group_name,
      "StackId" => { "Ref" => "AWS::StackId" },
      "WindowsOU" => windows_ou,
      "TrenddsmUrl" => Defaults.trend_dsm_url,
      "TrendPolicyName" => Defaults.component_name_tag(component_name: component_name),
      "AwsCliSource" => Context.environment.variable('aws_cli_source', ''),
      "AwsCfnSource" => Context.environment.variable('aws_cfn_source', ''),
      "AwsCfnSourcepy" => Context.environment.variable('aws_cfn_source_py', ''),
      "SSMPlatformVariablePath" => _ssm_platform_secret_path
    }

    case platform
    when :amazon_linux, :rhel, :centos
      user_data = UserData.load_aws_userdata(
        "#{__dir__}/aws_autoscale/linux-deploy.sh",
        user_data_variables
      )
    when :windows
      user_data = UserData.load_aws_userdata(
        "#{__dir__}/aws_autoscale/windows-deploy.ps1",
        user_data_variables
      )
    end

    asg_security_groups = [Context.component.sg_id(@component_name, "AsgSecurityGroup"), Context.asir.source_sg_id]
    asg_security_groups << Context.asir.destination_sg_id if ingress?

    # Build metadata hash
    bucket_name = Context.s3.artefact_bucket_name
    artefact_path = Defaults.cd_artefact_path(component_name: component_name)

    # If no bake instance specified, load artefacts in deploy stage
    metadata = if @bake_instance.any?
                 [
                   _metadata_pre_deploy(platform),
                   _metadata_post_deploy(platform)
                 ].inject(&:merge)
               else
                 [
                   _metadata_pre_prepare(platform, bucket_name, artefact_path),
                   _metadata_pre_deploy(platform),
                   _metadata_post_deploy(platform),
                   _metadata_auth(@component_name, bucket_name)
                 ].inject(&:merge)
               end

    _process_launch_configuration(
      template: template,
      launch_configuration_definition: @launch_configuration,
      image_id: image_id,
      platform: platform,
      user_data: user_data,
      instance_profile: { "Ref" => "InstanceProfile" },
      security_group_ids: asg_security_groups,
      metadata: metadata
    )

    # Generate AutoScalingGroup with blank = true to start at size 0
    _process_autoscaling_group(
      template: template,
      platform: platform,
      autoscaling_group_definition: @autoscaling_group,
      load_balancer_name: @load_balancer_name,
      launch_template_name: @launch_template_name,
      launch_configuration_name: @launch_configuration_name
    )

    # Generate scheduled actions
    _process_scheduled_actions(
      template: template,
      scheduled_actions: @scheduled_actions,
      autoscaling_group_name: @autoscaling_group_name
    )

    _process_alarms(
      template: template,
      alarm_definitions: @alarms,
    )

    _process_platform_secret_attachments(
      template: template,
      autoscaling_group_name: @autoscaling_group_name,
      execution_role_arn: Context.component.role_arn(component_name, "LambdaSecretManagementExecutionRole"),
      notification_role_arn: Context.component.role_arn(component_name, "AutoscalingNotificationRole"),
      notification_attachments: _platform_secrets_metadata,
      component_name: @component_name,
    )

    # Process volume attachments
    if @volume_attachments.any?
      _process_volume_attachments(
        template: template,
        autoscaling_group_name: @autoscaling_group_name,
        execution_role_arn: Context.component.role_arn(component_name, "LambdaExecutionRole"),
        notification_role_arn: Context.component.role_arn(component_name, "AutoscalingNotificationRole"),
        volume_attachments: _parse_volume_attachments(@volume_attachments)
      )
    end

    # Process network attachments
    if @network_attachments.any?
      _process_network_attachments(
        template: template,
        autoscaling_group_name: @autoscaling_group_name,
        execution_role_arn: Context.component.role_arn(component_name, "LambdaExecutionRole"),
        notification_role_arn: Context.component.role_arn(component_name, "AutoscalingNotificationRole"),
        network_attachments: _parse_network_attachments(@network_attachments)
      )
    end

    # Process lifecycle hooks
    if @lifecycle_hooks.any?
      _process_lifecycle_hooks(
        template: template,
        lifecycle_hooks: @lifecycle_hooks,
        autoscaling_group_name: @autoscaling_group_name,
        role_arn: Context.component.role_arn(component_name, "AutoscalingNotificationRole"),
      )
    end

    if @backup_policy.any?

      policy_definitions = _parse_instance_backup_policy(
        resource_id: { 'Ref' => @autoscaling_group_name },
        definitions: @backup_policy,
        component_name: @component_name
      )

      _process_backup_policy(
        template: template,
        backup_policy: policy_definitions
      )

    end

    # Process Route53 deployment decords
    unless Defaults.ad_dns_zone? || @load_balancer.empty?
      _process_deploy_r53_dns_records(
        template: template,
        component_name: @component_name,
        zone: Defaults.r53_hosted_zone,
        resource_records: ['Fn::GetAtt' => [@load_balancer_name, 'DNSName']],
        ttl: '60',
        type: 'CNAME'
      )
    end

    return template
  end
end