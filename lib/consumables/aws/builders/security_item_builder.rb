module SecurityItemBuilder
  def _process_security_items(
    template: nil,
    vpc_id: nil,
    security_items: nil
  )

    security_items.each do |security_item|
      case security_item["Type"]
      when "SecurityGroup"
        _build_sg(template: template, vpc_id: vpc_id, security_item: security_item)
      when "Role"
        _build_role(template: template, security_item: security_item)
      else
        Log.error "Unknown security item type #{security_item["Type"].inspect}"
      end
    end
  end

  def _build_sg(template: nil, vpc_id: nil, security_item: nil)
    name = security_item["Name"]
    deletion_policy = security_item.fetch("DeletionPolicy", "Delete")

    # Generate the SecurityGroup resource
    template["Resources"][name] = {
      "Type" => "AWS::EC2::SecurityGroup",
      "DeletionPolicy" => deletion_policy,
      "Properties" => {
        "GroupDescription" => "Security group #{name}",
        "VpcId" => vpc_id
      }
    }

    # Generate the SecurityGroup GroupId output
    template["Outputs"] ||= {}
    template["Outputs"]["#{name}Id"] = {
      "Description" => "Id for security group #{name}",
      "Value" => { "Fn::GetAtt" => [name, "GroupId"] },
    }
  end

  def _build_role(template: nil, security_item: nil)
    name = security_item["Name"]
    service = security_item["Service"] || "ec2.amazonaws.com"

    # Generate the Role resource
    template["Resources"][name] = {
      "Type" => "AWS::IAM::Role",
      "Properties" => {
        "AssumeRolePolicyDocument" => {
          "Version" => "2012-10-17",
          "Statement" => [
            {
              "Effect" => "Allow",
              "Principal" => {
                "Service" => [service]
              },
              "Action" => ["sts:AssumeRole"]
            }
          ]
        },
        "Path" => "/",
      }
    }

    Log.info "Initiating: setting permission boundary policy in the current build roles"
    template["Resources"][name]["Properties"]["PermissionsBoundary"] = { "Fn::Sub" => "arn:aws:iam::${AWS::AccountId}:policy/#{Defaults.permission_boundary_policy}" }
    Log.info "Completed: successfully set permission boundary policy in the current build roles"

    managed_policy_arns = Array(security_item["ManagedPolicyArns"])
    template["Resources"][name]["Properties"]["ManagedPolicyArns"] = managed_policy_arns unless managed_policy_arns.empty?

    # Generate the Role Arn output
    template["Outputs"] ||= {}
    template["Outputs"]["#{name}Arn"] = {
      "Description" => "Arn for role #{name}",
      "Value" => { "Fn::GetAtt" => [name, "Arn"] },
    }
  end
end
