module WaitConditionBuilder
  def _process_wait_condition(
    template: nil,
    name: "Wait",
    count: 1,
    timeout: 1800
  )

    template["Resources"][name] = {
      "Type" => "AWS::CloudFormation::WaitConditionHandle",
      "Properties" => {}
    }

    template["Resources"]["#{name}Condition"] = {
      "Type" => "AWS::CloudFormation::WaitCondition",
      "Properties" => {
        "Count" => "#{count}",
        "Handle" => { "Ref" => name },
        "Timeout" => "#{timeout}",
      }
    }
  end
end
