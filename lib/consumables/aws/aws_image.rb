# Builds aws/image component
# component stands up a single AWS::Instance resource, snapshots and creates AMI
# DNS txt record is used to reference resulting artifact by other components.

require "consumable"
require "util/user_data"
require "util/obj_to_text"
require "util/tag_helper"
require_relative "builders/instance_builder"
require_relative "builders/instance_profile_builder"
require_relative "builders/route53_record_builder"
require_relative "builders/dns_record_builder"

# @attr_reader bake_instance [Hash] definition for EC2 Instance resource used for baking
# @attr_reader bake_instance_name [String] name for the baking instance resource
class AwsImage < Consumable
  include InstanceBuilder
  include InstanceProfileBuilder
  include Route53RecordBuilder
  include DnsRecordBuilder

  attr_reader :bake_instance, :bake_instance_name

  # @param (see Consumable#initialize)
  def initialize(component_name, definition)
    super(component_name, definition)

    @bake_instance = {}

    # Load resources from the component definition
    (definition["Configuration"] || {}).each do |name, resource|
      type = resource["Type"]

      case type
      when "AWS::EC2::Instance"
        raise "This component does not support multiple #{type} resources" unless @bake_instance.empty?

        @bake_instance[name] = resource
      when nil
        raise "Must specify a type for resource #{name.inspect}"
      else
        raise "Resource type #{type.inspect} is not supported by this component"
      end
    end

    # Assign default names to unspecified resources
    @bake_instance = { "BakeInstance" => {} } if @bake_instance.empty?
    @bake_instance_name = @bake_instance.keys.first

    # Gather backup tags from definition if available.
    @custom_image_prefix = JsonTools.get(
      @bake_instance.values.first, "Properties.Pipeline::CustomImagePrefix", nil
    )

    # Flag for encrypting AMI
    @encrypt_copy = JsonTools.get(@bake_instance.values.first, "Properties.Pipeline::EncryptImage", false)

    # Ensure the image conforms to standard to allow for subsequent builds to work out platform
    unless @custom_image_prefix.nil?
      if AwsHelper.ec2_platform_from_image(@custom_image_prefix, nil) == :unknown
        raise "Unable to determine platform from the custom_image_name variable: #{@custom_image_prefix}" \
          "Ensure to include platform specific identifier as part of the image name."
      end
    end
  end

  # @return (see Consumable#security_items)
  def security_items
    [
      {
        "Name" => "SecurityGroup",
        "Type" => "SecurityGroup",
        "Component" => @component_name
      },
      {
        "Name" => "InstanceRole",
        "Type" => "Role",
        "Component" => @component_name,
        "ManagedPolicyArns" => Context.asir.managed_policy_arn_list
      }
    ]
  end

  # @return (see Consumable#security_rules)
  def security_rules
    # Different security rules during bake and deploy
    security_rules = []

    security_rules += _instance_base_security_rules(component_name: @component_name)
    security_rules += _platform_security_rules(destination: "#{@component_name}.SecurityGroup")
    security_rules += _instance_baketime_security_rules(component_name: @component_name)

    security_rules += _parse_security_rules(
      type: :ip,
      rules: @bake_instance.values[0]["Security"],
      destination: "#{@component_name}.SecurityGroup"
    )

    return security_rules
  end

  def deploy
    # Determine SOE details
    soe_alias = JsonTools.get(@bake_instance.values[0], "Properties.ImageId", "@default")
    soe_ami = Defaults.image_by_dns(soe_alias) || Defaults.soe_ami_id(soe_alias)
    soe_ami_details = AwsHelper.ec2_get_image_details(soe_ami)
    soe_tags = soe_ami_details[:tags]
    soe_ami_id = soe_ami_details[:id]
    soe_ami_name = soe_ami_details[:name]
    platform = soe_ami_details[:platform]

    raise "Cannot determine operating system type of image #{soe_ami_id}" \
      " (ImageName = #{soe_ami_name}, Alias = #{soe_alias})" if platform == :unknown

    _upload_cd_artefacts(
      component_name: @component_name,
      platform: platform,
      soe_ami_id: soe_ami_id,
      objects: {}
    )

    # Create the baketime security rules
    _update_security_rules(rules: security_rules)

    # Use custom_image_name property if specified
    image_name = if @custom_image_prefix.nil?
                   Defaults.image_name(soe_ami_name, @component_name)
                 else
                   _custom_image_name(Context.component.replace_variables(@custom_image_prefix).gsub(/[^\w]/, '-').downcase)
                 end

    # Create the bake instance
    _build_bake_stack(
      soe_ami_id: soe_ami_id,
      soe_tags: soe_tags,
      image_name: image_name,
      soe_ami_name: soe_ami_name,
      platform: platform
    )

    # Create an image from our bake instance

    tags = Defaults.get_tags(@component_name)
    tags += TagHelper.get_tag_values(tags: soe_tags, default_value: image_name, tag_key: 'SOE_ID')

    # Build the bake image
    source_image = AwsHelper.ec2_shutdown_instance_and_create_image(
      Context.component.variable(@component_name, "#{@bake_instance_name}Id"),
      image_name,
      tags
    )

    bamboo_variables = Context.environment.dump_variables
    @kms_key_id = bamboo_variables["ami_kms_key"]

    if !@kms_key_id
      Log.debug "AMI KMS key not set in Bamboo variables. Using Application CMK."
      @kms_key_id = Context.kms.secrets_key_arn
    end

    # If encrypt flag is set we create an encrypted copy with the specified key
    if @encrypt_copy
      Log.debug "Creating an encrypted copy of EC2 AMI #{source_image.inspect} using Application CMK #{Context.kms.secrets_key_arn}"
      outputs = AwsHelper.ec2_copy_image(
        source_image_id: source_image["ImageId"],
        name: source_image["ImageName"],
        tags: tags,
        encrypted: @encrypt_copy,
        kms_key_id: @kms_key_id
      )

      # Delete the unencrypted source
      Log.debug "Created Encrypted EC2 AMI #{outputs["ImageId"]}. Deleting unencrypted source AMI #{source_image.inspect}"
      AwsHelper.ec2_delete_image(source_image["ImageId"])

    # Otherwise we carry on with the bake image created
    else
      outputs = source_image
    end

    Context.component.set_variables(
      @component_name,
      "ImageId" => outputs["ImageId"],
      "ImageName" => outputs["ImageName"]
    )

    Log.output "#{@component_name} - ImageId: #{outputs['ImageId']}, ImageName: #{outputs['ImageName']}"

    unless Defaults.ad_dns_zone?
      Log.debug "Deploying Route53 DNS records"
      # Replace resources in the component stack with DNS record resources only
      deploy_r53_dns_records(template: { "Resources" => {}, "Outputs" => {} })
    else
      # Delete component stack if we don't need it
      begin
        stack_id = Context.component.variable(@component_name, "StackId", nil)
        AwsHelper.cfn_delete_stack(stack_id) unless stack_id.nil?
      rescue => e
        Log.warn "Failed to delete component #{@component_name.inspect} stack #{stack_id.inspect} during teardown - #{e}"
      end

      begin
        Log.debug "Deploying AD DNS records"
        dns_name = Defaults.deployment_dns_name(
          component: @component_name,
          zone: Defaults.ad_dns_zone
        )

        endpoint = Context.component.variable(
          @component_name,
          "ImageId"
        )

        deploy_ad_dns_records(
          dns_name: dns_name,
          endpoint: endpoint,
          type: 'TXT',
          ttl: '60'
        )
      rescue => e
        Log.error "Failed to deploy DNS records - #{e}"
        raise "Failed to deploy DNS records - #{e}"
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

    # Delete stack if it still exists
    begin
      stack_id = Context.component.stack_id(@component_name)
      AwsHelper.cfn_delete_stack(stack_id) unless stack_id.nil?
    rescue => e
      exception ||= e
      Log.warn "Failed to delete stack #{stack_id.inspect} during teardown - #{e}"
    end

    # Deregister AMI and delete instance snapshot
    begin
      override = Context.environment.variable('image_teardown_protection', nil)
      if override.to_s != 'true'
        ami_id = Context.component.variable(@component_name, "ImageId", nil)
        AwsHelper.ec2_delete_image(ami_id) unless ami_id.nil?
      else
        Log.info "Skipping teardown of the image #{ami_id} - image_teardown_protection is set to true"
      end
    rescue => e
      exception ||= e
      Log.warn "Failed to delete AMI #{ami_id.inspect} during teardown - #{e}"
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

  private

  # Returns composite custom image name with appended version
  # @param prefix [String] Prefix for custom image name
  def _custom_image_name(prefix)
    custom_image_name = AwsHelper.ec2_versioned_image_name(
      prefix: prefix,
      owners: [Context.environment.account_id]
    )

    Log.debug "Custom Image incremented name: #{custom_image_name}"
    custom_image_name
  end

  # @param (see AwsAutoscale#_build_bake_stack)
  def _build_bake_stack(soe_ami_id: nil, soe_ami_name: nil, platform: nil, soe_tags: nil, image_name: nil)
    Log.info "Creating bake instance from SOE AMI #{soe_ami_id} (#{soe_ami_name})"
    stack_name = Defaults.component_stack_name(@component_name)
    tags = Defaults.get_tags(@component_name)
    tags += TagHelper.get_tag_values(tags: soe_tags, default_value: image_name, tag_key: 'SOE_ID')

    template = _bake_instance_template(
      image_id: soe_ami_id,
      platform: platform
    )
    Context.component.set_variables(@component_name, { "BakeTemplate" => template })

    begin
      stack_outputs = {}
      stack_outputs = AwsHelper.cfn_create_stack(
        stack_name: stack_name,
        template: template,
        tags: tags
      )
    rescue ActionError => e
      stack_outputs = e.partial_outputs
      raise "Failed to create instance bake stack - #{e}"
    ensure
      Context.component.set_variables(@component_name, stack_outputs)

      # Copy all the produced log files to a local log directory
      AwsHelper.s3_download_objects(
        bucket: Context.s3.artefact_bucket_name,
        prefix: Defaults.log_upload_path(component_name: component_name, type: "bake"),
        local_path: "#{Defaults.logs_dir}/#{@component_name}/bake",
        validate: false
      )
    end
  end

  # @param (see AwsAutoscale#_bake_instance_template)
  def _bake_instance_template(
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
      "AwsCfnSourcepy" => Context.environment.variable('aws_cfn_source_py', ''),
    }

    case platform
    when :amazon_linux, :rhel, :centos
      user_data = UserData.load_aws_userdata(
        "#{__dir__}/aws_autoscale/linux-bake.sh",
        user_data_variables
      )
    when :windows
      user_data = UserData.load_aws_userdata(
        "#{__dir__}/aws_autoscale/windows-bake.ps1",
        user_data_variables
      )
    end

    security_group_ids = [
      Context.component.sg_id(@component_name, "SecurityGroup"),
      Context.asir.source_sg_id
    ]
    security_group_ids << Context.asir.destination_sg_id if ingress?

    # Build metadata for instance deployment
    bucket_name = Context.s3.artefact_bucket_name
    artefact_path = Defaults.cd_artefact_path(component_name: component_name)

    metadata = [
      _metadata_pre_prepare(platform, bucket_name, artefact_path),
      _metadata_bake_post_deploy(platform),
      _metadata_auth(@component_name, bucket_name)
    ].inject(&:merge)

    _process_instance(
      template: template,
      instance_definition: @bake_instance,
      user_data: user_data,
      security_group_ids: security_group_ids,
      image_id: image_id,
      instance_profile: { "Ref" => "InstanceProfile" },
      shutdown_behaviour: "stop",
      metadata: metadata
    )

    return template
  end

  def deploy_r53_dns_records(template: nil)
    _process_deploy_r53_dns_records(
      template: template,
      component_name: @component_name,
      zone: Defaults.r53_hosted_zone,
      resource_records: ["\"#{Context.component.variable(@component_name, "ImageId")}\""],
      ttl: '60',
      type: 'TXT'
    )

    begin
      stack_id = Context.component.stack_id(@component_name)
      AwsHelper.cfn_update_stack(
        stack_name: stack_id,
        template: template,
        wait_delay: 10,
        max_attempts: 30
      )
    rescue => error
      Log.error "Failed to update component #{@component_name} stack #{stack_id} - #{error}"
      raise "Failed to update component #{@component_name} stack #{stack_id} - #{error}"
    end
  end
end
