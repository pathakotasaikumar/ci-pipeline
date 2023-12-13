require 'consumable'
require_relative 'builders/load_balancing_v2_load_balancer_builder'
require_relative 'builders/load_balancing_v2_listener_builder'
require_relative 'builders/load_balancing_v2_listener_rule_builder'
require_relative 'builders/load_balancing_v2_target_group_builder'
require_relative 'builders/route53_record_builder'
require_relative 'builders/dns_record_builder'

# Extends Consumable class
# Builds aws/alb pipeline component
class AwsAlb < Consumable
  include LoadBalancingV2LoadBalancerBuilder
  include LoadBalancingV2ListenerBuilder
  include LoadBalancingV2ListenerRuleBuilder
  include LoadBalancingV2TargetGroupBuilder
  include Route53RecordBuilder
  include DnsRecordBuilder

  # @param (see Consumable#initialize)
  def initialize(component_name, definition)
    super(component_name, definition)

    @load_balancer = {}
    @listeners = {}
    @listener_rules = {}
    @target_groups = {}

    # Load resources from the component definition
    (definition["Configuration"] || {}).each do |name, resource|
      type = resource["Type"]

      case type
      when "AWS::ElasticLoadBalancingV2::LoadBalancer"
        raise "This component does not support multiple #{type} resources" unless @load_balancer.empty?

        @load_balancer[name] = resource
      when "AWS::ElasticLoadBalancingV2::Listener"
        @listeners[name] = resource
      when "AWS::ElasticLoadBalancingV2::ListenerRule"
        @listener_rules[name] = resource
      when "AWS::ElasticLoadBalancingV2::TargetGroup"
        @target_groups[name] = resource
      when "Pipeline::Features"
        @features[name] = resource
      when nil
        raise "Must specify a type for resource #{name.inspect}"
      else
        raise "Resource type #{type.inspect} is not supported by this component"
      end
    end

    @load_balancer_name = @load_balancer.keys.first
  end

  # @return (see Consumable#security_items)
  def security_items
    [
      {
        "Name" => "SecurityGroup",
        "Type" => "SecurityGroup",
        "Component" => @component_name
      }
    ]
  end

  # @return (see Consumable#security_rules)
  def security_rules
    # Different security rules during bake and deploy
    _parse_security_rules(
      type: :ip,
      rules: @load_balancer.values.first["Security"],
      destination: "#{@component_name}.SecurityGroup"
    )
  end

  # Run deploy actions
  def deploy
    # Create stack
    stack_name = Defaults.component_stack_name(@component_name)
    tags = Defaults.get_tags(@component_name)
    @pipeline_features.map { |f| tags += f.feature_tags }
    template = _template
    Context.component.set_variables(@component_name, "Template" => template)

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
      Context.component.set_variables(@component_name, stack_outputs)
    end

    # Create DNS name for this component
    return unless Defaults.ad_dns_zone?

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

    # Delete component stack
    begin
      stack_id = Context.component.stack_id(@component_name)
      AwsHelper.cfn_delete_stack(stack_id) unless stack_id.nil?
    rescue => e
      exception ||= e
      Log.warn "Failed to delete stack #{stack_id.inspect} during teardown - #{e}"
    end

    # Clean up deployment DNS record
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
    name_records = custom_name_records(component_name: @component_name, content: @listeners, pattern: '@wildcard-qcpaws')

    raise 'Name records must be an Hash.' unless name_records.is_a?(Hash)

    return name_records
  end

  private

  # Create a new CloudFormation template with all resources required for the component
  # @return [Hash] CloudFormation template template returned as reference
  def _template
    template = { "Resources" => {}, "Outputs" => {} }

    # Process ALB template
    security_groups = [Context.component.sg_id(@component_name, 'SecurityGroup')]
    security_groups << Context.asir.destination_sg_id if ingress?

    _process_load_balancing_v2_load_balancer(
      template: template,
      load_balancer_definition: @load_balancer,
      security_group_ids: security_groups
    )

    _process_load_balancing_v2_target_group(
      template: template,
      target_group_definition: @target_groups,
      vpc_id: Context.environment.vpc_id
    )

    _process_load_balancing_v2_listener(
      template: template,
      listener_definition: @listeners,
      load_balancer: @load_balancer_name
    )

    _process_load_balancing_v2_listener_rule(
      template: template,
      listener_rule_definition: @listener_rules
    )

    # Process Route53 deployment records
    unless Defaults.ad_dns_zone?
      _process_deploy_r53_dns_records(
        template: template,
        component_name: @component_name,
        zone: Defaults.r53_hosted_zone,
        resource_records: ['Fn::GetAtt' => [@load_balancer_name, 'DNSName']],
        ttl: '60',
        type: 'CNAME'
      )
    end

    template
  end
end
