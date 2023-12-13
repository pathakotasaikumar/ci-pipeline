# Helper module used to generate AWS::AutoScaling::LaunchConfiguration resources

require_relative "util/metadata_builder"
require "util/json_tools"
require "pricing/ec2"

module LaunchConfigurationBuilder
  # Generates a CloudFormation AWS::AutoScaling::LaunchConfiguration resource
  #
  # @param template [Hash] template definition to generate resource into
  # @param launch_configuration_definition [Hash] launch configuration properties
  # @param image_id [String] id of the AMI to launch with this launch configuration
  # @param user_data [String,Hash] launch configuration userdata string or hash
  # @param instance_profile [String,Hash] instance profile to associate with this launch configuration
  # @param security_group_ids [Array] list of security group arrays
  # @param metadata [Hash] launch configuration resource metadata

  def _process_launch_configuration(
    template: nil,
    launch_configuration_definition: nil,
    image_id: nil,
    user_data: nil,
    instance_profile: nil,
    platform: nil,
    security_group_ids: nil,
    metadata: nil
  )
    name, definition = launch_configuration_definition.first

    metadata ||= {}
    metadata[:user_metadata] = JsonTools.get(definition, "Metadata", {})
    metadata = MetadataBuilder.build(**metadata)

    # Create LaunchConfiguration template snippet
    template["Resources"][name] = {
      "Type" => "AWS::AutoScaling::LaunchConfiguration",
      "Metadata" => metadata,
      "Properties" => {
        "IamInstanceProfile" => instance_profile,
        "ImageId" => image_id,
        "SecurityGroups" => security_group_ids,
        "UserData" => user_data,
      }
    }
    resource = template["Resources"][name]

    JsonTools.transfer(definition, "Properties.KeyName", resource)
    JsonTools.transfer(definition, "Properties.BlockDeviceMappings", resource)
    JsonTools.transfer(definition, "Properties.SpotPrice", resource)

    instance_type = JsonTools.get(definition, "Properties.InstanceType", "m3.medium")
    resource["Properties"]["InstanceType"] = instance_type

    tenancy = JsonTools.get(definition, "Properties.PlacementTenancy", nil)
    resource["Properties"]["PlacementTenancy"] = tenancy unless tenancy.nil?

    spot_alias = JsonTools.get(definition, "Properties.SpotPrice", nil)

    if !spot_alias.nil?
      spot_bid = Pricing::EC2.process_ec2_spot_price(
        spot_alias: spot_alias,
        platform: platform,
        instance_type: instance_type,
        tenancy: tenancy
      )

      resource["Properties"]["SpotPrice"] = spot_bid
    end
  end
end
