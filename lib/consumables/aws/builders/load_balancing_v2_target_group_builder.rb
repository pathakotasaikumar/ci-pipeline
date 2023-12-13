require "util/json_tools"
require_relative "lambda_permission_builder"

# Create AWS::LoadBalancingV2::TargetGroup resource
module LoadBalancingV2TargetGroupBuilder
  include LambdaPermissionBuilder
  # Generate AWS::LoadBalancingV2::TargetGroup resource
  # @param template [Hash] CloudFormation template passed in as reference
  # @param target_group_definition [Hash] Listener resource parsed from YAML definition
  # @param vpc_id [String] VPC for the TargetGroup resource
  def _process_load_balancing_v2_target_group(
    template:,
    target_group_definition:,
    vpc_id:
  )
    target_group_definition.each do |name, definition|
      Context.component.replace_variables(definition)

      target_type = JsonTools.get(definition, "Properties.TargetType", "instance")
      case target_type
      when "instance", "ip"
        _process_load_balancing_v2_target_group_nonlambda(
          template: template,
          name: name,
          definition: definition,
          vpc_id: vpc_id,
          target_type: target_type
        )
      when "lambda"
        _process_load_balancing_v2_target_group_lambda(
          template: template,
          name: name,
          definition: definition
        )
      end

      template["Outputs"]["#{name}Arn"] = {
        "Description" => "Target Group Arn",
        "Value" => { "Ref" => name }
      }

      # Outputs of TargetGroupFullName
      template["Outputs"]["#{name}TargetGroupFullName"] = {
        "Description" => "Target Group Full Name",
        "Value" => { 'Fn::GetAtt' => [name, 'TargetGroupFullName'] }
      }

      # Outputs of TargetGroupName
      template["Outputs"]["#{name}TargetGroupName"] = {
        "Description" => "Target Group Name",
        "Value" => { 'Fn::GetAtt' => [name, 'TargetGroupName'] }
      }
    end
  end

  def _process_load_balancing_v2_target_group_nonlambda(
    template:,
    name:,
    definition:,
    vpc_id:,
    target_type: "instance"
  )
    template["Resources"][name] = {
      "Type" => "AWS::ElasticLoadBalancingV2::TargetGroup",
      "Properties" => {
        "Port" => JsonTools.get(definition, "Properties.Port"),
        "Protocol" => JsonTools.get(definition, "Properties.Protocol"),
        "TargetType" => target_type,
        "VpcId" => vpc_id
      }
    }

    resource = template["Resources"][name]
    JsonTools.transfer(definition, "Properties.HealthCheckIntervalSeconds", resource)
    JsonTools.transfer(definition, "Properties.HealthCheckPath", resource)
    JsonTools.transfer(definition, "Properties.HealthCheckPort", resource)
    JsonTools.transfer(definition, "Properties.HealthCheckProtocol", resource)
    JsonTools.transfer(definition, "Properties.HealthCheckTimeoutSeconds", resource)
    JsonTools.transfer(definition, "Properties.HealthyThresholdCount", resource)
    JsonTools.transfer(definition, "Properties.Matcher", resource)
    JsonTools.transfer(definition, "Properties.TargetGroupAttributes", resource)
    JsonTools.transfer(definition, "Properties.Targets", resource)
    JsonTools.transfer(definition, "Properties.UnhealthyThresholdCount", resource)
  end

  def _process_load_balancing_v2_target_group_lambda(
    template:,
    name:,
    definition:
  )

    # According to cloudformatino spec, there can only be a single function target
    targets = JsonTools.get(definition, "Properties.Targets")
    _process_lambda_permission(
      template: template,
      permissions: {
        "#{name}ELBLambdaPermission" => {
          "Properties" => {
            "Action" => "lambda:InvokeFunction",
            "FunctionName" => targets[0]["Id"],
            "Principal" => "elasticloadbalancing.amazonaws.com"
          }
        }
      }
    )

    template["Resources"][name] = {
      "DependsOn" => "#{name}ELBLambdaPermission",
      "Type" => "AWS::ElasticLoadBalancingV2::TargetGroup",
      "Properties" => {
        "TargetType" => "lambda",
        "Targets" => targets,
      }
    }

    resource = template["Resources"][name]
    JsonTools.transfer(definition, "Properties.HealthCheckEnabled", resource)
    JsonTools.transfer(definition, "Properties.HealthCheckIntervalSeconds", resource)
    JsonTools.transfer(definition, "Properties.HealthCheckTimeoutSeconds", resource)
    JsonTools.transfer(definition, "Properties.HealthyThresholdCount", resource)
    JsonTools.transfer(definition, "Properties.Matcher", resource)
    JsonTools.transfer(definition, "Properties.TargetGroupAttributes", resource)
    JsonTools.transfer(definition, "Properties.UnhealthyThresholdCount", resource)
  end
end
