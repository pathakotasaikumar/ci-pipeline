module DbInstanceAuroraBuilder
  include DbInstanceBuilder
  def _process_db_instances(
    template: nil,
    db_instance_definitions: nil,
    db_parameter_group:,
    db_cluster_name: nil,
    engine_name: "aurora",
    component_name: nil,
    dependsOn: nil
  )

    db_instance_definitions.each do |name, definition|
      zone_alias = JsonTools.get(definition, "Properties.AvailabilityZone", nil)

      zone = zone_alias.nil? ? nil : Context.environment.availability_zones(zone_alias)[0]

      template["Resources"][name] = {
        "Type" => "AWS::RDS::DBInstance",
        "Properties" => {
          "DBInstanceIdentifier" => Defaults.resource_name(component_name, name),
          "Engine" => JsonTools.get(definition, "Properties.Engine", engine_name),
          "CopyTagsToSnapshot" => true,
          "DBSubnetGroupName" => { "Ref" => "DBSubnetGroup" },
          "DBClusterIdentifier" => { "Ref" => db_cluster_name }
        }
      }

      resource = template["Resources"][name]
      resource = AwsHelper.performanceinsight(definition, resource, Context.kms.secrets_key_arn)

      JsonTools.transfer(definition, "Properties.DBParameterGroupName", resource)
      _process_db_parameter_group(
        resource: resource,
        db_parameter_group: db_parameter_group
      )


      JsonTools.transfer(definition, "Properties.DBInstanceClass", resource, "db.t3.medium")
      resource["Properties"]["DBInstanceClass"] = _replace_db_instance_class(resource["Properties"]["DBInstanceClass"])

      resource["Properties"]["AvailabilityZone"] = zone unless zone.nil?
      resource["DependsOn"] = dependsOn unless dependsOn.nil?

      template["Outputs"]["#{name}EndpointAddress"] = {
        "Description" => "RDS instance #{name} endpoint",
        "Value" => { "Fn::GetAtt" => [name, "Endpoint.Address"] }
      }

      template["Outputs"]["#{name}Port"] = {
        "Description" => "RDS instance #{name} port",
        "Value" => { "Fn::GetAtt" => [name, "Endpoint.Port"] }
      }

      template["Outputs"]["#{name}Arn"] = {
        "Description" => "RDS instance #{name} ARN",
        "Value" => { "Fn::Join" => [":", ["arn:aws:rds", { "Ref" => "AWS::Region" }, { "Ref" => "AWS::AccountId" }, "db", { "Ref" => name }]] }
      }
    end
  end

  def _process_db_parameter_group(resource:, db_parameter_group:)
    if !resource["Properties"].key?("DBParameterGroupName") && db_parameter_group.any?
      resource["Properties"]["DBParameterGroupName"] = { "Ref" => db_parameter_group.keys[0] }
    end
  end
end
