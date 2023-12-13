require "util/json_tools"

module ScalingPolicyBuilder
  def _process_scaling_policies(
    template: nil,
    scaling_policy_definitions: nil,
    autoscaling_group_name: nil
  )
    scaling_policy_definitions.each do |name, definition|
      template["Resources"][name] = {
        "Type" => "AWS::AutoScaling::ScalingPolicy",
        "Properties" => {
          "AdjustmentType" => JsonTools.get(definition, "Properties.AdjustmentType", "ChangeInCapacity"),
          "AutoScalingGroupName" => { "Ref" => autoscaling_group_name },
          "PolicyType" => JsonTools.get(definition, "Properties.PolicyType", "SimpleScaling")
        }
      }

      resource = template["Resources"][name]

      JsonTools.transfer(definition, "Properties.PolicyType", resource)
      JsonTools.transfer(definition, "Properties.StepAdjustments", resource)

      estimated_instance_warmup = JsonTools.get(definition, "Properties.EstimatedInstanceWarmup", nil)
      step_adjustments = JsonTools.get(definition, "Properties.StepAdjustments", nil)
      cooldown = JsonTools.get(definition, "Properties.Cooldown", nil)
      scaling_adjustment = JsonTools.get(definition, "Properties.ScalingAdjustment", nil)

      policy_type =  resource["Properties"]["PolicyType"]

      if policy_type == "SimpleScaling"
        if scaling_adjustment != nil
          resource["Properties"]["ScalingAdjustment"] = JsonTools.get(definition, "Properties.ScalingAdjustment").to_s
        else
          resource["Properties"]["ScalingAdjustment"] = "1"
        end
        if cooldown != nil
          resource["Properties"]["Cooldown"] = JsonTools.get(definition, "Properties.Cooldown").to_s
        else
          resource["Properties"]["Cooldown"] = "300"
        end
      end

      unless estimated_instance_warmup.nil?
        resource["Properties"]["EstimatedInstanceWarmup"] = JsonTools.get(definition, "Properties.EstimatedInstanceWarmup").to_s
      end

      unless step_adjustments.nil? || step_adjustments.empty? || policy_type != "StepScaling"
        resource["Properties"]["StepAdjustments"] = JsonTools.get(definition, "Properties.StepAdjustments")
      end
    end
  end
end
