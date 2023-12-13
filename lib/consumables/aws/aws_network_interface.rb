require "consumable"
require_relative "builders/network_interface_builder"
require_relative "builders/route53_record_builder"
require_relative 'builders/dns_record_builder'

class AwsNetworkInterface < Consumable
  include NetworkInterfaceBuilder
  include Route53RecordBuilder
  include DnsRecordBuilder

  # @param (see Consumable#initialize)
  def initialize(component_name, definition)
    super(component_name, definition)

    @network_interface = {}

    # Load resources from the component definition
    (definition["Configuration"] || {}).each do |name, resource|
      type = resource["Type"]

      case type
      when "AWS::EC2::NetworkInterface"
        if @network_interface.any?
          raise "This component does not support multiple #{type} resources"
        end

        @network_interface[name] = resource
      when nil
        raise "Must specify a type for resource #{name}"
      else
        raise "Resource type #{type} is not supported by this component"
      end
    end

    if @network_interface.empty?
      raise "Must specify an AWS::EC2::NetworkInterface resource"
    end

    @network_interface_name = @network_interface.keys.first
  end

  def security_items
    [
      {
        "Name" => "SecurityGroup",
        "Type" => "SecurityGroup",
        "Component" => component_name
      }
    ]
  end

  def security_rules
    definition = @network_interface.values.first
    security_rules = []

    mappings = {}
    mappings['read'] = %w(
      ec2:AttachNetworkInterface
      ec2:DescribeNetworkInterfaceAttribute
      ec2:DescribeNetworkInterfaces
      ec2:DetachNetworkInterface
    )

    mappings['admin'] = %w(
      ec2:ModifyNetworkInterfaceAttribute
      ec2:ResetNetworkInterfaceAttribute
    )

    security_rules += _parse_security_rules(
      type: :iam,
      mappings: mappings,
      rules: definition["Security"],
      # TODO: lock down to specific ENI ARN when AWS supports resource-level policies for the ENI APIs..
      destination: "*"
    )

    return security_rules
  end

  def deploy
    # Create stack
    stack_name = Defaults.component_stack_name(component_name)
    tags = Defaults.get_tags(component_name)
    template = _build_template

    Context.component.set_variables(component_name, "Template" => template)
    stack_outputs = {}

    begin
      stack_outputs = AwsHelper.cfn_create_stack(
        stack_name: stack_name,
        template: template,
        tags: tags
      )
    rescue => e
      stack_outputs = e.is_a?(ActionError) ? e.partial_outputs : {}
      raise "Failed to create stack - #{e}"
    ensure
      Context.component.set_variables(component_name, stack_outputs)
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
        "#{@network_interface_name}PrimaryPrivateIpAddress"
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

  def release
    super
  end

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

  def _build_template
    template = { "Resources" => {}, "Outputs" => {} }

    security_group_ids = [
      Context.component.sg_id(component_name, "SecurityGroup"),
      Context.asir.source_sg_id
    ]

    security_group_ids << Context.asir.destination_sg_id if ingress?

    _process_network_interface(
      template: template,
      network_interface_definition: @network_interface,
      security_group_ids: security_group_ids
    )

    unless Defaults.ad_dns_zone?
      _process_deploy_r53_dns_records(
        template: template,
        component_name: @component_name,
        zone: Defaults.r53_hosted_zone,
        resource_records: ['Fn::GetAtt' => [@network_interface_name, 'PrimaryPrivateIpAddress']],
        ttl: '60',
        type: 'A'
      )
    end

    return template
  end
end
