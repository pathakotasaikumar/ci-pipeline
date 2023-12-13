require 'consumable'
require_relative 'builders/route53_record_builder'
require_relative 'builders/route53_healthcheck_builder'
require_relative 'builders/dns_record_builder'
# Extends Consumable class
# Builds aws/route53 pipeline component
class AwsRoute53 < Consumable
  include Route53RecordBuilder
  include Route53HealthCheckBuilder
  include DnsRecordBuilder

  # @param (see Consumable#initialize)
  def initialize(component_name, definition)
    super(component_name, definition)

    @records = {}
    @healthchecks = {}

    # Load resources from the component definition
    (definition['Configuration'] || {}).each do |name, resource|
      type = resource['Type']

      case type
      when 'AWS::Route53::RecordSet'
        @records[name] = resource
      when 'AWS::Route53::Record'
        @records[name] = resource
      when 'AWS::Route53::HealthCheck'
        @healthchecks[name] = resource
      when 'Pipeline::Features'
        @features[name] = resource
      when nil
        raise "Must specify a type for resource #{name.inspect}"
      else
        raise "Resource type #{type.inspect} is not supported by this component"
      end
    end

    zones = @records.values.map { |value|
      JsonTools.get(value, "Properties.HostedZoneName", nil)
    }.compact.uniq
    raise "More than a single HostedZoneName found for aws/route53 component #{zones}" if zones.size > 1

    @zone = zones.first || Defaults.r53_dns_zone
  end

  # @return (see Consumable#security_items)
  def security_items
    []
  end

  # @return (see Consumable#security_rules)
  def security_rules
    []
  end

  def deploy
    # Deploy stack
    Log.info "Creating stack"
    stack_name = Defaults.component_stack_name(@component_name)
    template = _build_template

    tags = Defaults.get_tags(@component_name)
    @pipeline_features.map { |f| tags += f.feature_tags }
    stack_outputs = {}
    begin
      stack_outputs = AwsHelper.cfn_create_stack(
        stack_name: stack_name,
        template: template,
        tags: tags
      )
    rescue ActionError => e
      stack_outputs = e.partial_outputs
      raise "Failed to create stack - #{e}"
    ensure
      Context.component.set_variables(@component_name, stack_outputs)
    end
  end

  def release
    super
  end

  def teardown
    exception = nil

    # Delete stack
    begin
      stack_id = Context.component.stack_id(@component_name)
      AwsHelper.cfn_delete_stack(stack_id) unless stack_id.nil?
    rescue => e
      exception ||= e
      Log.warn "Failed to delete stack #{stack_id.inspect} during teardown - #{e}"
    end
    raise exception unless exception.nil?
  end

  def name_records
    {
      'DeployDnsName' => Defaults.deployment_dns_name(
        component: component_name,
        zone: @zone
      ),
      'ReleaseDnsName' => Defaults.release_dns_name(
        component: component_name,
        zone: Defaults.dns_zone
      )
    }
  end

  private

  # Builds out AWS::Route53::RecordSet and other required resources
  # @return [Hash] CloudFormation template representation
  def _build_template
    template = { "Resources" => {}, "Outputs" => {} }

    dns_name = Defaults.deployment_dns_name(
      component: component_name,
      zone: @zone
    )

    Log.output("#{@component_name} DNS: #{dns_name}")

    _process_route53_records(
      template: template,
      record_name: dns_name,
      record_sets: @records
    )

    _process_route53_healthcheck(
      template: template,
      healthchecks: @healthchecks
    )

    return template
  end
end
