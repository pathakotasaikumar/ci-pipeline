require_relative 'db_instance_builder'

module DbInstanceSqlserverBuilder
  include DbInstanceBuilder

  def _process_db_instances(
    template: nil,
    db_instance_definitions: nil,
    security_group_ids: nil,
    db_parameter_group: nil,
    db_option_group: nil,
    snapshot_identifier: nil,
    component_name: nil,
    dependsOn: nil
  )

    db_instance_definitions.each do |name, definition|
      template["Resources"][name] = {
        "Type" => "AWS::RDS::DBInstance",
        "Properties" => {
          "DBInstanceIdentifier" => Defaults.resource_name(component_name, name),
          "DBSubnetGroupName" => { "Ref" => "DBSubnetGroup" },
          "CopyTagsToSnapshot" => true,
          "PubliclyAccessible" => false,
          "VPCSecurityGroups" => security_group_ids,
        }
      }
      resource = template["Resources"][name]

      resource["Properties"]["DBParameterGroupName"] = { "Ref" => db_parameter_group.keys[0] } unless db_parameter_group.empty?
      resource["Properties"]["OptionGroupName"] = { "Ref" => db_option_group.keys[0] } unless db_option_group.empty?

      if Defaults.sections[:env] == "prod" || Context.environment.qa?
        JsonTools.transfer(definition, "DeletionPolicy", resource, "Snapshot")
      else
        JsonTools.transfer(definition, "DeletionPolicy", resource, "Delete")
      end

      engine = JsonTools.get(definition, "Properties.Engine", "sqlserver-se")
      resource["Properties"]["Engine"] = engine
      resource["Properties"]["StorageEncrypted"] = true
      resource["DependsOn"] = dependsOn unless dependsOn.nil?

      timezone=JsonTools.get(definition, "Properties.Timezone", nil)

      if !timezone.nil?
        resource["Properties"]["Timezone"] = timezone
      end

      case engine
      when "sqlserver-ex", "sqlserver-web"
        resource["Properties"]["LicenseModel"] = "license-included"
      when "sqlserver-se"
        JsonTools.transfer(definition, "Properties.LicenseModel", resource, "license-included")
      when "sqlserver-ee"
        JsonTools.transfer(definition, "Properties.LicenseModel", resource, "bring-your-own-license")
      else
        raise "Unsupported database engine #{engine.inspect}"
      end
      resource = AwsHelper.performanceinsight(definition, resource, Context.kms.secrets_key_arn)

      JsonTools.transfer(definition, "Properties.DBInstanceClass", resource)
      JsonTools.transfer(definition, "Properties.Iops", resource)
      JsonTools.transfer(definition, "Properties.Port", resource, "1433")
      JsonTools.transfer(definition, "Properties.StorageType", resource, "gp2")

      if !snapshot_identifier.nil?
        resource["Properties"]["DBSnapshotIdentifier"] = snapshot_identifier
        JsonTools.transfer(definition, "Properties.AllocatedStorage", resource)
        JsonTools.transfer(definition, "Properties.BackupRetentionPeriod", resource, "30")
        JsonTools.transfer(definition, "Properties.EngineVersion", resource)
        JsonTools.transfer(definition, "Properties.MultiAZ", resource, true)
      else
        # Create new database
        JsonTools.transfer(definition, "Properties.AllocatedStorage", resource, "200")
        JsonTools.transfer(definition, "Properties.AllowMajorVersionUpgrade", resource, false)
        JsonTools.transfer(definition, "Properties.AutoMinorVersionUpgrade", resource, true)
        JsonTools.transfer(definition, "Properties.BackupRetentionPeriod", resource, "30")
        JsonTools.transfer(definition, "Properties.DBInstanceClass", resource, "db.t3.medium")
        JsonTools.transfer(definition, "Properties.EngineVersion", resource)
        JsonTools.transfer(definition, "Properties.MultiAZ", resource, true)
        JsonTools.transfer(definition, "Properties.PreferredBackupWindow", resource)
        JsonTools.transfer(definition, "Properties.PreferredMaintenanceWindow", resource)

        secrets_key_arn = Context.kms.secrets_key_arn

        if secrets_key_arn.nil?
          raise "KMS key for application service #{Defaults.kms_secrets_key_alias} was not found."
        end

        resource["DBInstanceClass"] = _replace_db_instance_class(resource["DBInstanceClass"]) unless !resource["DBInstanceClass"]
        resource["Properties"]["KmsKeyId"] = secrets_key_arn

        _process_db_login(
          template: template,
          resource_name: name,
          component_name: component_name,
          master_user_name: JsonTools.get(
            definition, "Properties.MasterUsername", 'root'
          ),
          master_user_password: JsonTools.get(
            definition, "Properties.MasterUserPassword", GeneratePassword.generate
          )
        )

      end

      template["Outputs"]["#{name}EndpointAddress"] = {
        "Description" => "RDS instance #{name} endpoint",
        "Value" => { "Fn::GetAtt" => [name, "Endpoint.Address"] }
      }

      template["Outputs"]["#{name}EndpointPort"] = {
        "Description" => "RDS instance #{name} port",
        "Value" => { "Fn::GetAtt" => [name, "Endpoint.Port"] }
      }

      template["Outputs"]["#{name}Arn"] = {
        "Description" => "RDS instance #{name} ARN",
        "Value" => { "Fn::Join" => [":", ["arn:aws:rds", { "Ref" => "AWS::Region" }, { "Ref" => "AWS::AccountId" }, "db", { "Ref" => name }]] }
      }
    end
  end
end
