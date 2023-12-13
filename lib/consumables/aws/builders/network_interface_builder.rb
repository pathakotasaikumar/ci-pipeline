module NetworkInterfaceBuilder
  def _process_network_interface(
    template: nil,
    network_interface_definition: nil,
    security_group_ids: nil
  )
    name, definition = network_interface_definition.first

    # Determine subnet id and availability zone to place instance into
    subnet_alias = JsonTools.get(definition, "Properties.SubnetId", "@a-private")
    subnet_id = Context.environment.subnet_ids(subnet_alias)[0]

    template["Resources"][name] = {
      "Type" => "AWS::EC2::NetworkInterface",
      "Properties" => {
        "GroupSet" => security_group_ids,
        "SourceDestCheck" => JsonTools.get(definition, "Properties.SourceDestCheck", true),
        "SubnetId" => subnet_id,
      }
    }
    resource = template["Resources"][name]

    JsonTools.transfer(definition, "Properties.PrivateIpAddress", resource)
    JsonTools.transfer(definition, "Properties.PrivateIpAddresses", resource)
    JsonTools.transfer(definition, "Properties.SecondaryPrivateIpAddressCount", resource)

    # ENI id
    template["Outputs"]["#{name}Id"] = {
      "Description" => "ENI id",
      "Value" => { "Ref" => name },
    }
    # ARN
    template["Outputs"]["#{name}Arn"] = {
      "Description" => "ENI ARN",
      "Value" => { "Fn::Join" => ["/", [{ "Fn::Join" => [":", ["arn:aws:ec2", { "Ref" => "AWS::Region" }, { "Ref" => "AWS::AccountId" }, "network-interface"]] }, { "Ref" => name }]] }
    }
    # Primary IP address
    template["Outputs"]["#{name}PrimaryPrivateIpAddress"] = {
      "Description" => "Primary private IP address",
      "Value" => { "Fn::GetAtt" => [name, "PrimaryPrivateIpAddress"] },
    }
    # CSV of secondary IP addresses
    template["Outputs"]["#{name}SecondaryPrivateIpAddresses"] = {
      "Description" => "Primary private IP address",
      "Value" => { "Fn::Join" => [",", { "Fn::GetAtt" => [name, "SecondaryPrivateIpAddresses"] }] },
    }
  end
end
