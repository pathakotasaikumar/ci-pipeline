require "util/json_tools"

# Module is responsible for generating autoscaling group CloudFormation resource
module ApplicationAutoscalingBuilder
  # @param template [Hash] CloudFormation template passed in as reference
  # @param scalable_target [Hash] Scalable target resource parsed from YAML definition
  # @param scaling_policy [Hash] Scaling Policy target resource parsed from YAML definition
  # @param service_name_space [String] Logical name for a service
  # @param service_role_arn [String] ARN for the autoscaling service role
  def _process_application_autoscaling_group(
    template:,
    component_name:,
    scalable_target:,
    scaling_policy:,
    service_name_space:,
    service_role_arn: nil,
    resource_id: nil
  )

    # We need to maintain backward compat with the original autoscaling target with DynamoDB
    # The non-dynamodb version takes in a resource id and uses the service link role
    if service_name_space == "dynamodb"
      _process_application_autoscaling_targets_dynamodb(
        template: template,
        scalable_target: scalable_target,
        service_name_space: "dynamodb",
        service_role_arn: service_role_arn,
      )
    else
      _process_application_autoscaling_targets(
        template: template,
        scalable_target: scalable_target,
        service_name_space: service_name_space,
        resource_id: resource_id,
      )
    end

    _process_application_autoscaling_policies(
      template: template,
      component_name: component_name,
      service_name_space: service_name_space,
      scaling_policy: scaling_policy,
      resource_id: resource_id,
    )
  end

  # This is the original function pre-ECS which only caters for DynamoDB.
  # It has some very restricted type casting like ResourceId being an array to be joined,
  # which doesn"t work well with all the other non-dynamodb resources.
  #
  # @param template [Hash] CloudFormation template passed in as reference
  # @param scalable_target [Hash] Scalable target resource parsed from YAML definition
  # @param service_name_space [String] Logical name for a service
  # @param service_role_arn [String] ARN for the autoscaling service role
  def _process_application_autoscaling_targets_dynamodb(
    template:,
    scalable_target:,
    service_name_space:,
    service_role_arn:
  )
    scalable_target.each do |name, definition|
      resource_id = JsonTools.get(definition, "Properties.ResourceId", [])

      raise "The #{name}  AWS::ApplicationAutoScaling::ScalableTarget Resource id value cannot be empty and must be array." if resource_id.empty? || !resource_id.is_a?(Array)

      template["Resources"][name] = {
        "Type" => "AWS::ApplicationAutoScaling::ScalableTarget",
        "Properties" => {
          "ServiceNamespace" => service_name_space,
          "ResourceId" => {
            "Fn::Join" => ["/", resource_id]
          },
          "RoleARN" => service_role_arn
        }
      }

      resource = template["Resources"][name]
      JsonTools.transfer(definition, "Properties.MaxCapacity", resource)
      JsonTools.transfer(definition, "Properties.MinCapacity", resource)
      JsonTools.transfer(definition, "Properties.ScalableDimension", resource)

      template["Outputs"]["#{name}Name"] = {
        "Description" => "Scalable Target Name",
        "Value" => { "Ref" => name }
      }
    end
  end

  def _process_application_autoscaling_targets(
    template:,
    scalable_target:,
    service_name_space:,
    resource_id:
  )
    scalable_target.each do |name, definition|
      template["Resources"][name] = {
        "Type" => "AWS::ApplicationAutoScaling::ScalableTarget",
        "Properties" => {
          "MaxCapacity" => JsonTools.get(definition, "Properties.MaxCapacity"),
          "MinCapacity" => JsonTools.get(definition, "Properties.MinCapacity")
        }
      }

      properties = template["Resources"][name]["Properties"]

      properties["ScalableDimension"] = JsonTools.get(definition, "Properties.ScalableDimension")
      case properties["ScalableDimension"]
      when "ecs:service:DesiredCount"
        properties["ServiceNamespace"] = "ecs"
        properties["ResourceId"] = resource_id
        properties["RoleARN"] = {
          "Fn::Sub" => "arn:aws:iam::${AWS::AccountId}:role/aws-service-role/ecs.application-autoscaling.amazonaws.com/AWSServiceRoleForApplicationAutoScaling_ECSService"
        }
      end

      template["Outputs"]["#{name}Name"] = {
        "Description" => "Scalable Target Name",
        "Value" => { "Ref" => name }
      }
    end
  end

  # @param template [Hash] CloudFormation template passed in as reference
  # @param scaling_policy [Hash] Scaling Policy target resource parsed from YAML definition
  def _process_application_autoscaling_policies(
    template:,
    component_name:,
    service_name_space: nil,
    scaling_policy:,
    resource_id:
  )
    scaling_policy.each do |name, definition|
      template["Resources"][name] = {
        "Type" => "AWS::ApplicationAutoScaling::ScalingPolicy",
        "Properties" => {
        }
      }
      properties = template["Resources"][name]["Properties"]
      properties["PolicyName"] = JsonTools.get(definition, "Properties.PolicyName", Defaults.resource_name(component_name, name))
      properties["ScalingTargetId"] = JsonTools.get(definition, "Properties.ScalingTargetId")

      step_scaling_conf = JsonTools.get(definition, "Properties.StepScalingPolicyConfiguration", {})
      target_tracking_conf = JsonTools.get(definition, "Properties.TargetTrackingScalingPolicyConfiguration", {})
      # JsonTools.transfer(definition, "Properties.PolicyType", resource)
      if step_scaling_conf.any?
        properties["PolicyType"] = "StepScaling"
        properties["StepScalingPolicyConfiguration"] = Context.component.replace_variables(step_scaling_conf)
      elsif target_tracking_conf.any?
        properties["PolicyType"] = "TargetTrackingScaling"
        properties["TargetTrackingScalingPolicyConfiguration"] = Context.component.replace_variables(target_tracking_conf)
      end

      template["Outputs"]["#{name}Name"] = {
        "Description" => "Scaling Policy Name",
        "Value" => { "Ref" => name }
      }
    end
  end

  def _dynamodb_autoscaling_security_rules(component_name:)
    [
      IamSecurityRule.new(
        roles: "#{component_name}.AutoscalingScalingRole",
        actions: [
          "dynamodb:DescribeTable",
          "dynamodb:UpdateTable",
          "cloudwatch:PutMetricAlarm",
          "cloudwatch:DescribeAlarms",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:SetAlarmState",
          "cloudwatch:DeleteAlarms"
        ],
        resources: "*"
      )
    ]
  end
end
