require_relative 'db_instance_builder'

module DbInstanceOracleBuilder
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
          "CopyTagsToSnapshot" => true,
          "DBSubnetGroupName" => { "Ref" => "DBSubnetGroup" },
          "PubliclyAccessible" => false,
          "VPCSecurityGroups" => security_group_ids,
        }
      }
      resource = template["Resources"][name]

      unless db_parameter_group.nil? || db_parameter_group.empty?
        resource["Properties"]["DBParameterGroupName"] = { "Ref" => db_parameter_group.keys.first }
      end

      unless db_option_group.nil? || db_option_group.empty?
        resource["Properties"]["OptionGroupName"] = { "Ref" => db_option_group.keys.first }
      end

      if Defaults.sections[:env] == "prod" || Context.environment.qa?
        JsonTools.transfer(definition, "DeletionPolicy", resource, "Snapshot")
      else
        JsonTools.transfer(definition, "DeletionPolicy", resource, "Delete")
      end

      engine = JsonTools.get(definition, "Properties.Engine", "oracle-ee")
      resource["Properties"]["Engine"] = engine
      resource["Properties"]["StorageEncrypted"] = true
      resource["DependsOn"] = dependsOn unless dependsOn.nil?

      case engine
      when "oracle-se1", "oracle-se2"
        license_model = JsonTools.get(definition, "Properties.LicenseModel", "license-included")
      when "oracle-se", "oracle-ee"
        license_model = "bring-your-own-license"
      else
        raise "Unsupported database engine #{engine.inspect}"
      end
      resource["Properties"]["LicenseModel"] = license_model

      JsonTools.transfer(definition, "Properties.DBInstanceClass", resource)
      JsonTools.transfer(definition, "Properties.Iops", resource)
      JsonTools.transfer(definition, "Properties.Port", resource, "1521")
      JsonTools.transfer(definition, "Properties.StorageType", resource, "gp2")

      # For Oracle RDS, associated roles may be required for additional options on some services.
      # For example, S3 integration. Apart from OptionsGroup optionsettings, this role is required to write to S3
      
      associaterole = JsonTools.get(definition,"Properties.AssociatedRoles",nil)

      unless  associaterole.nil? || associaterole.empty?

        puts "Associated Roles #{associaterole}"
        JsonTools.transfer(definition, "Properties.AssociatedRoles", resource,nil)

      end
      resource = AwsHelper.performanceinsight(definition, resource, Context.kms.secrets_key_arn)

      if !snapshot_identifier.nil?
        resource["Properties"]["DBSnapshotIdentifier"] = snapshot_identifier
        JsonTools.transfer(definition, "Properties.AllowMajorVersionUpgrade", resource, false)
        JsonTools.transfer(definition, "Properties.AutoMinorVersionUpgrade", resource, true)
        JsonTools.transfer(definition, "Properties.AllocatedStorage", resource)
        JsonTools.transfer(definition, "Properties.BackupRetentionPeriod", resource, "30")
        JsonTools.transfer(definition, "Properties.EngineVersion", resource)
        JsonTools.transfer(definition, "Properties.MultiAZ", resource, true)
      else
        # Create new database
        # DBName must be specified
        db_name = JsonTools.get(definition, "Properties.DBName")
        unless db_name =~ /^[a-zA-Z]{1}[a-zA-Z0-9]{1,7}$/
          raise ArgumentError, "DBName must start with a letter, contain only"\
              " letters and numbers, and must be 2 to 8 characters long"
        end

        resource["Properties"]["DBName"] = db_name

        JsonTools.transfer(definition, "Properties.AllocatedStorage", resource, "100")
        JsonTools.transfer(definition, "Properties.AllowMajorVersionUpgrade", resource, false)
        JsonTools.transfer(definition, "Properties.AutoMinorVersionUpgrade", resource, true)
        JsonTools.transfer(definition, "Properties.BackupRetentionPeriod", resource, "30")
        JsonTools.transfer(definition, "Properties.CharacterSetName", resource)
        JsonTools.transfer(definition, "Properties.DBInstanceClass", resource, "db.t3.medium")
        JsonTools.transfer(definition, "Properties.EngineVersion", resource)
        JsonTools.transfer(definition, "Properties.MultiAZ", resource, true)
        JsonTools.transfer(definition, "Properties.PreferredBackupWindow", resource)
        JsonTools.transfer(definition, "Properties.PreferredMaintenanceWindow", resource)

        secrets_key_arn = Context.kms.secrets_key_arn
        if secrets_key_arn.nil?
          raise "KMS key for application service #{Defaults.kms_secrets_key_alias} was not found."
        end

        resource["DBInstanceClass"] = _replace_db_instance_class(resource["DBInstanceClass"]) if resource["DBInstanceClass"]
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
