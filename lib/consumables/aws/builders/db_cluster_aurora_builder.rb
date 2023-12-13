require_relative 'db_instance_builder'
# Module is responsible for providing a builder for AWS::RDS::DBCluster
module DbClusterAuroraBuilder
  include DbInstanceBuilder

  # Generated AWS::RDS::DBCluster resources
  # @param template [Hash] Template reference
  # @param db_cluster_definition [Hash] DB Cluster definition
  # @param security_group_ids [Array] list of security groups to be included
  # @param snapshot_identifier [String] Snapshot identifier
  # @param component_name [String] Name of the component
  # @param storage_encrypted [Bool] Storage encrypted?

  def _process_db_cluster(
    template: nil,
    db_cluster_definition: nil,
    db_cluster_parameters:,
    security_group_ids: nil,
    snapshot_identifier: nil,
    component_name: nil,
    storage_encrypted: true,
    engine_name: "aurora",
    engine_port: "3306",
    dependsOn: nil
  )

    db_cluster_definition.each do |name, definition|
      # Set pipeline managed properties and defaults

      Log.info "Processing the Database Engine"

      template["Resources"][name] = {
        "Type" => "AWS::RDS::DBCluster",
        "Properties" => {
          "DBClusterIdentifier" => Defaults.resource_name(component_name, name),
          "Engine" => JsonTools.get(definition, "Properties.Engine", engine_name),
          "DBSubnetGroupName" => { "Ref" => "DBSubnetGroup" },
          "VpcSecurityGroupIds" => security_group_ids,
        }
      }

      resource = template["Resources"][name]

      if Defaults.sections[:env] == "prod" || Context.environment.qa?
        JsonTools.transfer(definition, "DeletionPolicy", resource, "Snapshot")
      else
        JsonTools.transfer(definition, "DeletionPolicy", resource, "Delete")
      end

      JsonTools.transfer(definition, "Properties.DBClusterParameterGroupName", resource)
      _process_aurora_db_cluster_parameter_group(
        resource: resource,
        db_cluster_parameters: db_cluster_parameters
      )

      # Enforce encryption
      resource["Properties"]["StorageEncrypted"] = storage_encrypted

      # Set optional common user defined properties
      JsonTools.transfer(definition, "Properties.BackupRetentionPeriod", resource, 30)
      JsonTools.transfer(definition, "Properties.EngineVersion", resource)
      JsonTools.transfer(definition, "Properties.PreferredBackupWindow", resource)
      JsonTools.transfer(definition, "Properties.PreferredMaintenanceWindow", resource)
      JsonTools.transfer(definition, "Properties.Port", resource)

      if !snapshot_identifier.nil?
        resource["Properties"]["SnapshotIdentifier"] = snapshot_identifier
        engine_mode = JsonTools.get(definition, "Properties.EngineMode", "provisioned")
        
        if engine_mode == 'serverless'
          JsonTools.transfer(definition, "Properties.EngineMode", resource)
          resource["Properties"].delete("PreferredBackupWindow")
          resource["Properties"].delete("PreferredMaintenanceWindow")
        end

      else
        JsonTools.transfer(definition, "Properties.DatabaseName", resource)
        JsonTools.transfer(definition, "Properties.Port", resource, engine_port)
        # Set optional properties for aurora serverless
        engine_mode = JsonTools.get(definition, "Properties.EngineMode", "provisioned")

        if engine_mode == 'serverless'
          JsonTools.transfer(definition, "Properties.EngineMode", resource)
          JsonTools.transfer(definition, "Properties.EngineVersion", resource, "5.6.10a")
          JsonTools.transfer(definition, "Properties.ScalingConfiguration", resource)
        end

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

      if Context.kms.secrets_key_arn.nil?
        raise "KMS key for application service #{Defaults.kms_secrets_key_alias} was not found."
      end

      resource["Properties"]["KmsKeyId"] = Context.kms.secrets_key_arn if storage_encrypted
      resource["DependsOn"] = dependsOn unless dependsOn.nil?

      template["Outputs"]["#{name}EndpointAddress"] = {
        "Description" => "RDS cluster #{name} endpoint",
        "Value" => { "Fn::GetAtt" => [name, "Endpoint.Address"] }
      }

      template["Outputs"]["#{name}EndpointPort"] = {
        "Description" => "RDS cluster #{name} port",
        "Value" => { "Fn::GetAtt" => [name, "Endpoint.Port"] }
      }

      template["Outputs"]["#{name}Arn"] = {
        "Description" => "RDS Cluster #{name} ARN",
        "Value" => {
          "Fn::Join" => [":", ["arn:aws:rds", { "Ref" => "AWS::Region" }, {
            "Ref" => "AWS::AccountId"
          }, "cluster", {
            "Ref" => name
          }]]
        }
      }
      if engine_mode != 'serverless'
        template["Outputs"]["#{name}ReaderEndpointAddress"] = {
          "Description" => "RDS cluster #{name} endpoint",
          "Value" => _aurora_readonly_dns(name)
        }
      end
    end
  end

  def _process_aurora_db_cluster_parameter_group(resource:, db_cluster_parameters:)
    if !resource["Properties"].key?("DBClusterParameterGroupName") && db_cluster_parameters.any?
      resource["Properties"]["DBClusterParameterGroupName"] = {
        "Ref" => db_cluster_parameters.keys.first
      }
    end
  end

  def _aurora_readonly_dns(name)
    { "Fn::Join" => [".", [
      { "Fn::Select" => [0, { "Fn::Split" => [".", { "Fn::GetAtt" => [name, "Endpoint.Address"] }] }] },
      { "Fn::Join" => ["-", ["cluster-ro", { "Fn::Select" => [1, {
        "Fn::Split" => ["-", { "Fn::Select" => [1, {
          "Fn::Split" => [".", { "Fn::GetAtt" => [name, "Endpoint.Address"] }]
        }] }]
      }] }]] },
      { "Ref" => "AWS::Region" }, "rds.amazonaws.com"
    ]] }
  end
end
