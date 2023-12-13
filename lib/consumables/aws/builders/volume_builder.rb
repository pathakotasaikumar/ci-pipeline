module VolumeBuilder
  # Genrates template resource for AWS::EC2::Volume
  # @param template [Hash] Reference to a template
  # @param volume_definition [Hash] Volume definitions
  # @param snapshot_id [String] Snapshot identifier to be subs. into template.
  def _process_volume(
    template: nil,
    volume_definition: nil,
    snapshot_id: nil
  )
    name, definition = volume_definition.first

    zone_alias = JsonTools.get(definition, "Properties.AvailabilityZone")
    zone = Context.environment.availability_zones(zone_alias)[0]

    template["Resources"][name] = {
      "Type" => "AWS::EC2::Volume",
      "Properties" => {
        "AvailabilityZone" => zone,
        "VolumeType" => JsonTools.get(definition, "Properties.VolumeType", "gp3"),
      }
    }
    resource = template["Resources"][name]
    resource["Properties"]["Encrypted"] = true

    JsonTools.transfer(definition, "DeletionPolicy", resource)
    JsonTools.transfer(definition, "Properties.AutoEnableIO", resource)

    if resource["Properties"]["VolumeType"] == "io1" ||  resource["Properties"]["VolumeType"] == "io2"
      # Must specify IOPS if volume type is io1/io2
      JsonTools.transfer(definition, "Properties.Iops", resource, :error)
    end

    # Handle building from a snapshot
    if snapshot_id.nil?
      # No snapshot id was specified
      JsonTools.transfer(definition, "Properties.Size", resource, :error)

      secrets_key_arn = Context.kms.secrets_key_arn
      if secrets_key_arn.nil?
        raise "KMS key for application service #{Defaults.kms_secrets_key_alias} was not found."
      end

      resource["Properties"]["KmsKeyId"] = secrets_key_arn
    else
      # Snapshot id was specified - build volume from snapshot
      resource["Properties"]["SnapshotId"] = snapshot_id
      JsonTools.transfer(definition, "Properties.Size", resource)
    end

    template["Outputs"]["#{name}Id"] = {
      "Description" => "EBS volume id",
      "Value" => { "Ref" => name },
    }

    template["Outputs"]["#{name}Arn"] = {
      "Description" => "EBS volume ARN",
      "Value" => { "Fn::Join" => ["/", [{ "Fn::Join" => [":", ["arn:aws:ec2", { "Ref" => "AWS::Region" }, { "Ref" => "AWS::AccountId" }, "volume"]] }, { "Ref" => name }]] }
    }
  end
end
