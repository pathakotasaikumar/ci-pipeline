# Module responsible for construction AWS::Autoscaling::Lifecyclehook template
#
# Parameters:
# template: template carried into the module
# autoscaling_group_name: unique NAME for an autoscaling group to attach hook to
# notification_target_arn: sns topic ARN to send notification with metadata to
# role_arn: ARN of the role allowed to write to the notification target

module LifecycleHookBuilder
  def _process_lifecycle_hooks(
    template:,
    lifecycle_hooks:,
    autoscaling_group_name:,
    role_arn:
  )

    lifecycle_hooks.each do |name, definition|
      notification_target = JsonTools.get(definition, "Properties.NotificationTargetARN")
      if notification_target.is_a? String
        if notification_target.start_with? "arn:"
          notification_target_arn = notification_target
        else
          component_name, output_name = notification_target[1..-1].split(".", 2)
          notification_target_arn = Context.component.variable(component_name, output_name)
        end
      else
        notification_target_arn = notification_target
      end

      template["Resources"][name] = {
        "Type" => "AWS::AutoScaling::LifecycleHook",
        "Properties" => {
          "AutoScalingGroupName" => { "Ref" => autoscaling_group_name },
          "DefaultResult" => JsonTools.get(definition, "Properties.DefaultResult"),
          "LifecycleTransition" => JsonTools.get(definition, "Properties.LifecycleTransition"),
          "NotificationTargetARN" => notification_target_arn,
          "RoleARN" => role_arn,
        }
      }

      resource = template["Resources"][name]
      JsonTools.transfer(definition, "Properties.HeartbeatTimeout", resource)
      JsonTools.transfer(definition, "Properties.NotificationMetadata", resource)
    end
  end
end
