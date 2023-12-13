require 'util/json_tools'

# Create AWS::LoadBalancingV2::LoadBalancer resource
module LoadBalancingV2LoadBalancerBuilder
  # Generate AWS::LoadBalancingV2::LoadBalancer resource
  # @param template [Hash] CloudFormation template passed in as reference
  # @param load_balancer_definition [Hash] Listener resource parsed from YAML definition
  # @param security_group_ids [Array] List of security groups to be assigned to the LoadBalancer
  def _process_load_balancing_v2_load_balancer(
    template:,
    load_balancer_definition:,
    security_group_ids:
  )

    name, definition = load_balancer_definition.first

    scheme = JsonTools.get(definition, 'Properties.Scheme', 'internal')

    subnet_alias = JsonTools.get(definition, 'Properties.Subnets', scheme == 'internet-facing' ? '@public' : '@private')
    subnet_ids = Context.environment.subnet_ids(subnet_alias)

    template['Resources'][name] = {
      'Type' => 'AWS::ElasticLoadBalancingV2::LoadBalancer',
      'Properties' => {
        'IpAddressType' => JsonTools.get(definition, 'Properties.IpAddressType', 'ipv4'),
        'Scheme' => scheme,
        'Subnets' => subnet_ids,
        'Type' => JsonTools.get(definition, 'Properties.Type', 'application'),
      }
    }

    template['Resources'][name]['Properties']['SecurityGroups'] = security_group_ids unless template['Resources'][name]['Properties']['Type'] == 'network'

    resource = template['Resources'][name]
    JsonTools.transfer(definition, 'Properties.LoadBalancerAttributes', resource)

    # Outputs
    template['Outputs']["#{name}DNSName"] = {
      'Description' => 'ELB endpoint address',
      'Value' => { 'Fn::GetAtt' => [name, 'DNSName'] }
    }

    # Output for LoadBalancerFullName
    template["Outputs"]["#{name}FullName"] = {
      "Description" => "LoadBalancer Full Name",
      "Value" => { 'Fn::GetAtt' => [name, 'LoadBalancerFullName'] }
    }

    # Output for LoadBalancerFullName
    template["Outputs"]["#{name}Arn"] = {
      "Description" => "LoadBalancer Arn",
      "Value" => { 'Ref' => name }
    }
  end
end
