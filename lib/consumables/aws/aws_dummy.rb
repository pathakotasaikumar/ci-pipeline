require 'consumable'
require_relative 'builders/wait_condition_builder'
require_relative 'builders/dns_record_builder'

class AwsDummy < Consumable
  include WaitConditionBuilder
  include DnsRecordBuilder

  # @param (see Consumable#initialize)
  def initialize(component_name, definition)
    super(component_name, definition)
    raise "This feature is experimental. Please enquire with QCP in order to activate it." unless Context.environment.experimental?

    @dummy = {}

    # Load resources from the component definition
    (definition['Configuration'] || {}).each do |name, resource|
      type = resource['Type']

      case type
      when 'Pipeline::Dummy'
        raise "This component does not support multiple #{type} resources" unless @dummy.empty?

        @dummy[name] = resource
      when nil
        raise "Must specify a type for resource #{name.inspect}"
      else
        raise "Resource type #{type.inspect} is not supported by this component"
      end
    end

    # Assign default names to unspecified resources
    @dummy = {} if @dummy.empty?
  end

  # @return (see Consumable#security_items)
  def security_items
    [
      {
        'Name' => 'SecurityGroup',
        'Type' => 'SecurityGroup',
        'Component' => @component_name,
      }
    ]
  end

  # @return (see Consumable#security_rules)
  def security_rules
    # Different security rules during bake and deploy
    security_rules = []

    security_rules += _parse_security_rules(
      type: :ip,
      rules: @dummy.values[0]['Security'],
      destination: "#{@component_name}.SecurityGroup",
    )

    return security_rules
  end

  # Execute deployment steps for the component
  def deploy
    # Deploy stack
    Log.info "Creating stack"
    stack_name = Defaults.component_stack_name(@component_name)
    tags = Defaults.get_tags(@component_name)
    template = _full_template

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

      endpoint = "dummy"

      deploy_ad_dns_records(
        dns_name: dns_name,
        endpoint: endpoint,
        type: 'TXT',
        ttl: '60'
      )
    rescue => error
      Log.error "Failed to deploy DNS records - #{error}"
      raise "Failed to deploy DNS records - #{error}"
    end
  end

  # Execture release for the component
  def release
    super
  end

  # Execute teardown for the component stack
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

  private

  def _full_template
    template = { 'Resources' => {}, 'Outputs' => {} }

    template['Resources'][@dummy.keys[0]] = {
      'Type' => 'AWS::CloudFormation::WaitConditionHandle',
      'Properties' => {}
    }

    unless Defaults.ad_dns_zone?
      _process_deploy_r53_dns_records(
        template: template,
        component_name: @component_name,
        zone: Defaults.r53_hosted_zone,
        resource_records: ['dummy'],
        ttl: '60',
        type: 'TXT'
      )
    end
    return template
  end
end
