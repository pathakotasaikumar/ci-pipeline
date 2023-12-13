require "util/json_tools"

module InstanceProfileBuilder
  def _process_instance_profile(
    template: nil,
    instance_role_name: nil
  )

    # Generate InstanceProfile template snippet
    template["Resources"]["InstanceProfile"] = {
      "Type" => "AWS::IAM::InstanceProfile",
      "Properties" => {
        "Path" => "/",
        "Roles" => [instance_role_name],
      }
    }

    template["Outputs"]["InstanceProfileName"] = {
      "Description" => "Instance profile Name",
      "Value" => { "Ref" => "InstanceProfile" },
    }

    template["Outputs"]["InstanceProfileArn"] = {
      "Description" => "Instance profile ARN",
      "Value" => { "Fn::GetAtt" => ["InstanceProfile", "Arn"] },
    }
  end
end
