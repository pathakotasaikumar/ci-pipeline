require "util/json_tools"

module ScheduledActionBuilder
  def _process_scheduled_actions(
    template: nil,
    scheduled_actions: nil,
    autoscaling_group_name: nil
  )

    scheduled_actions.each do |name, definition|
      template["Resources"][name] = {
        "Type" => "AWS::AutoScaling::ScheduledAction",
        "Properties" => {
          "AutoScalingGroupName" => { "Ref" => autoscaling_group_name },
        }
      }

      resource = template["Resources"][name]
      JsonTools.transfer(definition, "Properties.DesiredCapacity", resource)
      JsonTools.transfer(definition, "Properties.EndTime", resource)
      JsonTools.transfer(definition, "Properties.MaxSize", resource)
      JsonTools.transfer(definition, "Properties.MinSize", resource)
      JsonTools.transfer(definition, "Properties.Recurrence", resource)
      JsonTools.transfer(definition, "Properties.StartTime", resource)
    end
  end
end
