# Module responsible for generating AWS::EFS::FileSystem template
module EfsFileSystemBuilder
  # @param template [Hash] template carried into the function
  # @param file_system_definitions [Hash] definition for the EFS resource
  # See CloudFormation AWS::EFS::FileSystem documentation for valid property values
  # http://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-efs-filesystem.html
  def _process_efs_file_systems(
    template: nil,
    file_system_definitions: nil
  )

    file_system_definitions.each do |name, definition|
      template["Resources"][name] = {
        "Type" => "AWS::EFS::FileSystem",
        "Properties" => {
          "Encrypted" => true,
          "KmsKeyId" => Context.kms.secrets_key_arn,
          "PerformanceMode" => JsonTools.get(definition, "Properties.PerformanceMode", "generalPurpose"),
          "ThroughputMode" => JsonTools.get(definition, "Properties.ThroughputMode", "bursting")
        }
      }

#      ProvisionedThroughputInMibps = JsonTools.get(definition, "Properties.ProvisionedThroughputInMibps", nil)
      
      unless (JsonTools.get(definition, "Properties.ProvisionedThroughputInMibps", nil)).nil?
        template["Resources"][name]["Properties"]["ProvisionedThroughputInMibps"] = JsonTools.get(definition, "Properties.ProvisionedThroughputInMibps", nil)
      end
      
      backup_policy = { 'Status' => JsonTools.get(definition, "Properties.AutoBackupPolicy", "DISABLED") }

      unless (JsonTools.get(definition, "Properties.AutoBackupPolicy", "DISABLED")) == "DISABLED"
        template["Resources"][name]["Properties"]["BackupPolicy"] = backup_policy
      end


      template["Outputs"]["#{name}Id"] = {
        "Description" => "EFS file system id",
        "Value" => { "Ref" => name }
      }

      template["Outputs"]["#{name}Endpoint"] = {
        "Description" => "EFS file system endpoint",
        "Value" => {
          "Fn::Sub" => "${#{name}}.efs.${AWS::Region}.amazonaws.com"
        }
      }
    end
  end
end
