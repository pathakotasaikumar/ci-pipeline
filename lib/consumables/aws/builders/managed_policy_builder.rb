require "util/json_tools"

module ManagedPolicyBuilder
  def _process_managed_policy(
    template: nil,
    policy_definition: {}
  )
    name, definition = policy_definition.first

    # Generate the Role resource
    template["Resources"][name] = {
      "Type" => "AWS::IAM::ManagedPolicy",
      "Properties" => {
        "Path" => JsonTools.get(definition, "Properties.Path", "/"),
        "PolicyDocument" => {
          "Version" => JsonTools.get(definition, "Properties.PolicyDocument.Version", "2012-10-17"),
          "Statement" => JsonTools.get(definition, "Properties.PolicyDocument.Statement", []),
        },
      }
    }
    resource = template["Resources"][name]

    if resource["Properties"]["PolicyDocument"]["Statement"].empty?
      resource["Properties"]["PolicyDocument"]["Statement"] = [
        {
          "Sid" => "DummyStatement",
          "Effect" => "Allow",
          "Action" => ["s3:GetObject"],
          "Resource" => ["arn:aws:s3:::DUMMY_POLICY_STATEMENT"],
        }
      ]
    end

    # Generate the Role Arn output
    template["Outputs"] ||= {}
    template["Outputs"]["#{name}Arn"] = {
      "Description" => "ARN for policy #{name}",
      "Value" => { "Ref" => name },
    }
  end
end
