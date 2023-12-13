require_relative '../../consumable'

class AwsVPCEndpointService < Consumable
  # @param (see Consumable#initialize)
  def initialize(component_name, definition)
    super(component_name, definition)

    @endpoint_definition = {}

    # Load resources from the component definition
    (definition['Configuration'] || {}).each do |name, resource|
      type = resource['Type']

      case type
      when "AWS::EC2::VPCEndpointService"
        raise 'Multiple AWS::EC2::VPCEndpointService resources found' if @endpoint_definition.any?

        @endpoint_definition[name] = resource
      when 'Pipeline::Features'
        @features[name] = resource
      else
        raise "Resource type #{type.inspect} is not supported by this component"
      end
    end
  end

  def security_items
    security_items = []
    return security_items
  end

  def security_rules
    security_rules = []
    return security_rules
  end

  def deploy
    stack_name = Defaults.component_stack_name(@component_name)
    tags = Defaults.get_tags(@component_name)
    template = _full_template

    stack_outputs = {}
    begin
      stack_outputs = AwsHelper.cfn_create_stack(
        stack_name: stack_name,
        template: template,
        tags: tags
      )
    rescue ActionError => e
      stack_outputs = e.is_a?(ActionError) ? e.partial_outputs : {}
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

    # Delete component stack
    begin
      stack_id = Context.component.stack_id(@component_name)
      AwsHelper.cfn_delete_stack(stack_id) unless stack_id.nil?
    rescue => e
      exception ||= e
      Log.warn "Failed to delete stack #{stack_id.inspect} during teardown - #{e}"
    end

    raise exception unless exception.nil?
  end

  # @return [Hash] There's not output at all for endpoint service
  def name_records
    {}
  end

  private

  def _full_template
    template = { "Resources" => {} }
    name, definition = @endpoint_definition.first
    template["Resources"]["#{name}"] = {
      "Type" => "AWS::EC2::VPCEndpointService",
      "Properties" => {
        "AcceptanceRequired" => true,
      }
    }

    template["Resources"]["#{name}"]["Properties"]["NetworkLoadBalancerArns"] = Context.component.replace_variables(
      JsonTools.get(definition, 'Properties.NetworkLoadBalancerArns', [])
    )

    return template
  end
end
