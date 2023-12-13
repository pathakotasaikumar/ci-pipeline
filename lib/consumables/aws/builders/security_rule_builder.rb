# SecurityRuleBuilder will generate security rule resources for IP (SecurityGroupIngress) and IAM (Policy) linking.

require_relative "types/security_rule"

module SecurityRuleBuilder
  def _process_security_rules(
    template: nil, # Template Hash to populate with our generated AWS CloudFormation resources
    rules: nil, # Array of SecurityRule objects
    component_name: nil, # Name of the component for which these rules are being generated
    skip_non_existant: false # Set to true to skip security item references we cannot resolve, false to error
  )

    policy_statements = {}

    (rules || []).each do |rule|
      case rule
      when IpSecurityRule
        _build_ip_rule(
          template: template,
          rule: rule,
          skip_non_existant: skip_non_existant,
        )
      when IamSecurityRule
        # Generate and collect all the required policy statements into the policy_statements Hash
        _build_policy_statement(
          policy_statements: policy_statements,
          rule: rule,
          skip_non_existant: skip_non_existant,
        )
      else
        raise "Unknown security rule type #{rule.class.inspect}"
      end
    end

    # Build policies from the previously generated policy_statements Hash
    _build_policies(
      template: template,
      component_name: component_name,
      policy_statements: policy_statements,
      skip_non_existant: skip_non_existant,
    )
  end

  # Build SecurityGroupIngress resources for the specified source -> destination links
  def _build_ip_rule(template: nil, rule: nil, skip_non_existant: false)
    rule.ports.each do |port|
      if rule.destination.start_with? "sg-"
        # Destination is a direct security group reference
        destination_sg_id = rule.destination
      else
        # Destination is a reference to a security item - resolve the reference
        destination = rule.destination
        destination = destination[1..-1] if destination[0] == "@"
        component_name, sg_name = destination.split(".", 2)
        destination_sg_id = Context.component.sg_id(component_name, sg_name)
        if destination_sg_id.nil?
          next if skip_non_existant

          raise "Cannot find destination security group #{rule.destination.inspect}"
        end
      end

      if rule.sources.nil?
        next if skip_non_existant

        raise "IP rule source could not be resolved"
      end

      rule.sources.each do |source|
        resource_name = (rule.name || "#{source}On#{port.spec}").gsub(/[^a-zA-Z0-9]/, "x")[0...255]

        if source[0..0] =~ /[0-9]/
          template["Resources"][resource_name] = {
            "Type" => "AWS::EC2::SecurityGroupIngress",
            "Properties" => {
              "CidrIp" => source,
              "GroupId" => destination_sg_id,
              "IpProtocol" => port.protocol,
              "FromPort" => port.from,
              "ToPort" => port.to,
            },
          }
        else
          if source.start_with? "sg-"
            source_sg_id = source
          else
            # Source is a reference to a security item - resolve the reference
            source = source[1..-1] if source[0] == "@"
            component_name, sg_name = source.split(".", 2)
            source_sg_id = Context.component.sg_id(component_name, sg_name)
            if source_sg_id.nil?
              next if skip_non_existant
              raise "Cannot find source security group #{source.inspect}" if source_sg_id.nil?
            end
          end

          template["Resources"][resource_name] = {
            "Type" => "AWS::EC2::SecurityGroupIngress",
            "Properties" => {
              "SourceSecurityGroupId" => source_sg_id,
              "GroupId" => destination_sg_id,
              "IpProtocol" => port.protocol,
              "FromPort" => port.from,
              "ToPort" => port.to,
            },
          }
        end
      end
    end
  end

  # Build Policy statements to achieve the specified source -> destination links.
  # These statements will later need to be added to relevant policies to have any effect.
  def _build_policy_statement(policy_statements: nil, rule: nil, skip_non_existant: false)
    if rule.resources.nil? or rule.resources.empty?
      # No rule resources have been specified
      return if skip_non_existant

      raise "Policy statement resource could not be resolved (resources=#{rule.resources.inspect}; actions=#{rule.actions.inspect}; roles=#{rule.roles.inspect}; condition=#{rule.condition.inspect})"
    end

    if !rule.condition.nil? and JsonTools.contain_value?(rule.condition, nil)
      # Rule condition has been specified, but contains nil (unresolved) references
      return if skip_non_existant

      raise "One or more policy conditions could not be resolved (resources=#{rule.resources.inspect}; actions=#{rule.actions.inspect}; roles=#{rule.roles.inspect}; condition=#{rule.condition.inspect})"
    end

    resources = []
    rule.resources.each do |resource|
      if resource.nil? or resource.empty?
        # Resource has been specified, but contains nil (unresolved) references
        next if skip_non_existant

        raise "Policy statement resource could not be resolved (resources=#{rule.resources.inspect}; actions=#{rule.actions.inspect}; roles=#{rule.roles.inspect}; condition=#{rule.condition.inspect})"
      end
      resources << resource
    end

    rule.roles.each do |role|
      policy_statements[role] ||= []
      statement = {
        "Effect" => "Allow",
        "Action" => rule.actions,
        "Resource" => resources,
      }
      statement["Condition"] = rule.condition unless rule.condition.nil?

      policy_statements[role] << statement
    end
  end

  # Build IAM::Policy resources from the specified policy statements
  def _build_policies(template: nil, policy_statements: nil, component_name: nil, skip_non_existant: false)
    policy_statements.each do |role, statements|
      role = role[1..-1] if role[0] == "@"
      source_component, role_name = role.split(".", 2)
      role_id = Context.component.role_name(source_component, role_name)
      if role_id.nil?
        if skip_non_existant
          Log.debug "The skip_non_existant is set to #{skip_non_existant}, skipping to update the IAM::Policy statement for the IAM role #{role.inspect}"
          next
        end
        raise "Cannot find IAM role #{role.inspect}"
      end

      resource_name = "#{source_component}x#{role_name}x#{component_name}Policy".gsub(/[^a-zA-Z0-9]/, "x")[0...255]
      template["Resources"][resource_name] = {
        "Type" => "AWS::IAM::Policy",
        "Properties" => {
          "PolicyName" => Defaults.policy_name(component_name),
          "PolicyDocument" => {
            "Version" => "2012-10-17",
            "Statement" => statements,
          },
          "Roles" => [role_id],
        }
      }
    end
  end
end
