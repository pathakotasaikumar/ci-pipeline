require_relative 'db_instance_builder'

module DbInstancePostgresqlBuilder
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
          "Engine" => "postgres",
          "CopyTagsToSnapshot" => true,
          "PubliclyAccessible" => false,
          "VPCSecurityGroups" => security_group_ids,
        }
      }

      resource = template["Resources"][name]
      instance_id = JsonTools.get(definition, "Properties.SourceDBInstanceIdentifier", nil)

      unless db_parameter_group.nil? || db_parameter_group.empty?
        resource["Properties"]["DBParameterGroupName"] = { "Ref" => db_parameter_group.keys.first }
      end

      resource["Properties"]["DBSubnetGroupName"] = { "Ref" => "DBSubnetGroup" } if instance_id.nil?

      # Enforce encryption
      resource["Properties"]["StorageEncrypted"] = true
      resource["DependsOn"] = dependsOn unless dependsOn.nil?

      if Defaults.sections[:env] == "prod" || Context.environment.qa?
        JsonTools.transfer(definition, "DeletionPolicy", resource, "Snapshot")
      else
        JsonTools.transfer(definition, "DeletionPolicy", resource, "Delete")
      end

      JsonTools.transfer(definition, "Properties.AllocatedStorage", resource)
      JsonTools.transfer(definition, "Properties.DBInstanceClass", resource)
      JsonTools.transfer(definition, "Properties.Iops", resource)
      JsonTools.transfer(definition, "Properties.Port", resource, "5432")
      JsonTools.transfer(definition, "Properties.StorageType", resource, "gp2")
      resource = AwsHelper.performanceinsight(definition, resource, Context.kms.secrets_key_arn)

      if !instance_id.nil?
        # Configure a replica instance, assume the rest of properties copied from DB Instance
        resource["Properties"]["SourceDBInstanceIdentifier"] = { "Ref" => instance_id }

      elsif !snapshot_identifier.nil?
        resource["Properties"]["DBSnapshotIdentifier"] = snapshot_identifier
        JsonTools.transfer(definition, "Properties.MultiAZ", resource, true)
        JsonTools.transfer(definition, "Properties.BackupRetentionPeriod", resource, "30")
        JsonTools.transfer(definition, "Properties.AllowMajorVersionUpgrade", resource, false)
        JsonTools.transfer(definition, "Properties.AutoMinorVersionUpgrade", resource, true)
        JsonTools.transfer(definition, "Properties.BackupRetentionPeriod", resource, "30")
        JsonTools.transfer(definition, "Properties.EngineVersion", resource)
        JsonTools.transfer(definition, "Properties.PreferredBackupWindow", resource)
        JsonTools.transfer(definition, "Properties.PreferredMaintenanceWindow", resource)
      else
        # Create new database
        JsonTools.transfer(definition, "Properties.AllocatedStorage", resource, "100")
        JsonTools.transfer(definition, "Properties.DBInstanceClass", resource, "db.t3.medium")
        JsonTools.transfer(definition, "Properties.DBName", resource)
        JsonTools.transfer(definition, "Properties.EngineVersion", resource)
        JsonTools.transfer(definition, "Properties.MultiAZ", resource, true)
        JsonTools.transfer(definition, "Properties.AllowMajorVersionUpgrade", resource, false)
        JsonTools.transfer(definition, "Properties.AutoMinorVersionUpgrade", resource, true)
        JsonTools.transfer(definition, "Properties.BackupRetentionPeriod", resource, "30")
        JsonTools.transfer(definition, "Properties.PreferredBackupWindow", resource)
        JsonTools.transfer(definition, "Properties.PreferredMaintenanceWindow", resource)

        resource["DBInstanceClass"] = _replace_db_instance_class(resource["DBInstanceClass"]) if resource["DBInstanceClass"]
        secrets_key_arn = Context.kms.secrets_key_arn

        if secrets_key_arn.nil?
          raise "KMS key for application service #{Defaults.kms_secrets_key_alias} was not found."
        end

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
