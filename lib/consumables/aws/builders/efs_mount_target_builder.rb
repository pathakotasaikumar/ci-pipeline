# Module responsible for generating AWS::EFS::MountTarget template
module EfsMountTargetBuilder
  # @param template [Hash] template carried into the function
  # @param mount_target_definitions [Hash] definition for the EFS mount target definitions
  # See CloudFormation AWS::EFS::MountTarget documentation for valid property values
  # http://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-efs-mounttarget.html
  def _process_efs_mount_targets(
    template: nil,
    mount_target_definitions: nil
  )

    mount_target_definitions.each do |name, definition|
      template["Resources"][name] = {
        "Type" => "AWS::EFS::MountTarget",
        "Properties" => {
          "FileSystemId" => JsonTools.get(definition, "Properties.FileSystemId"),
          "SubnetId" => JsonTools.get(definition, "Properties.SubnetId"),
          "SecurityGroups" => JsonTools.get(definition, "Properties.SecurityGroups")
        }
      }

      template["Outputs"]["#{name}Id"] = {
        "Description" => "EFS mount target id",
        "Value" => { "Ref" => name }
      }
    end
  end
end
