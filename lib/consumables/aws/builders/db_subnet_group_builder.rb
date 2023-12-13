module DbSubnetGroupBuilder
  def _process_db_subnet_group(template: nil, db_subnet_group: nil)
    name, definition = db_subnet_group.first

    subnet_alias = JsonTools.get(definition, "Properties.SubnetIds", "@private")
    subnet_ids = Context.environment.subnet_ids(subnet_alias)

    template["Resources"][name] = {
      "Type" => "AWS::RDS::DBSubnetGroup",
      "Properties" => {
        "DBSubnetGroupDescription" => "Subnets available for the RDS DB Instance",
        "SubnetIds" => subnet_ids,
      }
    }

    template["Outputs"]["#{name}Arn"] = {
      "Description" => "RDS subnet group ARN",
      "Value" => { "Ref" => name }
    }
  end
end
