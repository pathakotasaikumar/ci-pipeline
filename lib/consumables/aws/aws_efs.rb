require "consumable"
require_relative "builders/alarm_builder"
require_relative "builders/efs_file_system_builder"
require_relative "builders/efs_mount_target_builder"
require_relative "builders/route53_record_builder"
require_relative "builders/dns_record_builder"

# Module is responsible for building AWS::EFS::FileSystem and associated CloudFormation resources
class AwsEfs < Consumable
  include AlarmBuilder
  include EfsFileSystemBuilder
  include EfsMountTargetBuilder
  include Route53RecordBuilder
  include DnsRecordBuilder

  # @param (see Consumable#initialize)
  def initialize(component_name, definition)
    super(component_name, definition)

    @alarms = {}
    @file_system = {}

    # Load resources from the component definition
    (definition["Configuration"] || {}).each do |name, resource|
      type = resource["Type"]

      case type
      when "AWS::CloudWatch::Alarm"
        @alarms[name] = resource
      when "AWS::EFS::FileSystem"
        raise "This component does not support multiple #{type} resources" unless @file_system.empty?

        @file_system[name] = resource
      when "Pipeline::Features"
        @features[name] = resource
      when nil
        raise "Must specify a type for resource #{name.inspect}"
      else
        raise "Resource type #{type.inspect} is not supported by this component"
      end
    end

    raise "Must specify an AWS::EFS::FileSystem resource" if @file_system.empty?

    @file_system_name = @file_system.keys.first
  end

  # @return (see Consumable#security_items)
  def security_items
    [
      {
        "Name" => "SecurityGroup",
        "Type" => "SecurityGroup",
        "Component" => @component_name,
      }
    ]
  end

  # @return (see Consumable#security_rules)
  def security_rules
    security_rules = []

    security_rules += _parse_security_rules(
      type: :ip,
      rules: @file_system.values.first["Security"],
      destination: "#{@component_name}.SecurityGroup"
    )

    return security_rules
  end

  # Execute deployment steps for the component
  def deploy
    # Create stack
    stack_name = Defaults.component_stack_name(@component_name)
    tags = Defaults.get_tags(@component_name)
    @pipeline_features.map { |f| tags += f.feature_tags }
    template = _build_template
    Context.component.set_variables(@component_name, "Template" => template)

    begin
      stack_outputs = {}
      stack_outputs = AwsHelper.cfn_create_stack(
        stack_name: stack_name,
        template: template,
        tags: tags
      )
    rescue => e
      stack_outputs = e.is_a?(ActionError) ? e.partial_outputs : {}
      raise "Failed to create stack - #{e}"
    ensure
      Context.component.set_variables(@component_name, stack_outputs)
    end
    return unless Defaults.ad_dns_zone?

    begin
      Log.debug "Deploying AD DNS records"

      dns_name = Defaults.deployment_dns_name(
        component: @component_name,
        zone: Defaults.ad_dns_zone
      )

      endpoint = Context.component.variable(
        @component_name,
        "#{@file_system_name}Endpoint"
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

  # Execute release for the component
  def release
    super
  end

  # Execute teardown for the component stack
  def teardown
    exception = nil

    # Delete component stack
    begin
      stack_id = Context.component.stack_id(@component_name)
      AwsHelper.cfn_delete_stack(stack_id) unless stack_id.nil?
    rescue => e
      exception ||= e
      Log.warn "Failed to delete stack #{stack_id.inspect} during teardown - #{e}"
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

  # Builds component CloudFormation template
  # @return [Hash] CloudFormation template representation
  def _build_template
    template = { "Resources" => {}, "Outputs" => {} }

    # Generate the EFS file system resource
    _process_efs_file_systems(
      template: template,
      file_system_definitions: @file_system
    )

    security_group_ids = [
      Context.component.sg_id(@component_name, "SecurityGroup"),
      Context.asir.source_sg_id
    ]
    security_group_ids << Context.asir.destination_sg_id if ingress?

    # Generate an EFS mount target for each private subnet
    mount_targets = {}
    Context.environment.subnet_ids("@private").each_with_index do |subnet_id, index|
      mount_targets["MountTarget#{subnet_id}".gsub(/[^a-zA-Z0-9]/, '')] = {
        "Type" => "AWS::EFS::MountTarget",
        "Properties" => {
          "FileSystemId" => { "Ref" => @file_system_name },
          "SubnetId" => subnet_id,
          "SecurityGroups" => security_group_ids
        }
      }
    end
    _process_efs_mount_targets(
      template: template,
      mount_target_definitions: mount_targets
    )

    # Generate CloudWatch alarms
    @alarms.values.each do |definition|
      definition["Properties"]["Namespace"] = "AWS/EFS"
      definition["Properties"]["Dimensions"] = [
        {
          "Name" => "FileSystemId",
          "Value" => { "Ref" => @file_system_name }
        }
      ]
    end
    _process_alarms(
      template: template,
      alarm_definitions: @alarms
    )

    unless Defaults.ad_dns_zone?
      _process_deploy_r53_dns_records(
        template: template,
        component_name: @component_name,
        zone: Defaults.r53_hosted_zone,
        resource_records: [
          { 'Fn::Sub' => "${#{@file_system_name}}.efs.${AWS::Region}.amazonaws.com" }
        ],
        ttl: '60',
        type: 'CNAME'
      )
    end

    return template
  end
end
