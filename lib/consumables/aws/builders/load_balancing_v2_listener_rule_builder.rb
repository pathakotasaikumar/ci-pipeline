require 'util/json_tools'

# Create AWS::LoadBalancingV2::ListenerRule resource
module LoadBalancingV2ListenerRuleBuilder
  # Generate AWS::LoadBalancingV2::ListenerRule resource
  # @param template [Hash] CloudFormation template passed in as reference
  # @param listener_rule_definition [Hash] Listener resource parsed from YAML definition
  def _process_load_balancing_v2_listener_rule(
    template:,
    listener_rule_definition:
  )

    listener_rule_definition.each do |name, definition|
      template['Resources'][name] = {
        'Type' => 'AWS::ElasticLoadBalancingV2::ListenerRule',
        'Properties' => {
          'Actions' => JsonTools.get(definition, 'Properties.Actions'),
          'Conditions' => JsonTools.get(definition, 'Properties.Conditions'),
          'ListenerArn' => JsonTools.get(definition, 'Properties.ListenerArn'),
          'Priority' => JsonTools.get(definition, 'Properties.Priority')
        }
      }
    end
  end
end
