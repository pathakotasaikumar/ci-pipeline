# Helper module used to generate AWS::EC2::LaunchTemplate resources

require_relative "util/metadata_builder"
require "util/json_tools"
require "pricing/ec2"

module LaunchTemplateBuilder
  # Generates a CloudFormation AWS::EC2::LaunchTemplate resource
  #
  # @param template [Hash] template definition to generate resource into
  # @param launch_template_definition [Hash] launch configuration properties
  # @param image_id [String] id of the AMI to launch with this launch configuration
  # @param user_data [String,Hash] launch configuration userdata string or hash
  # @param instance_profile [String,Hash] instance profile to associate with this launch configuration
  # @param security_group_ids [Array] list of security group arrays
  # @param metadata [Hash] launch template resource metadata

  def _process_launch_template_configuration(
    template: nil,
    launch_template_definition: nil,
    image_id: nil,
    user_data: nil,
    instance_profile: nil,
    platform: nil,
    security_group_ids: nil,
    metadata: nil
  )
    name, definition = launch_template_definition.first

    metadata ||= {}
    metadata[:user_metadata] = JsonTools.get(definition, "Metadata", {})
    metadata = MetadataBuilder.build(**metadata)
    instance_type = JsonTools.get(definition, "Properties.LaunchTemplateData.InstanceType", "m3.medium")
    # Create LaunchConfiguration template snippet
    template["Resources"][name] = {
      "Type" => "AWS::EC2::LaunchTemplate",
      "Metadata" => metadata,
      "Properties" => {
        "LaunchTemplateData" => {
          "IamInstanceProfile" => {
            "Name" => instance_profile
          },
          "InstanceType" => instance_type,
          "ImageId" => image_id,
          "SecurityGroupIds" => security_group_ids,
          "UserData" => user_data
        }
      }
    }
    launch_template_data = JsonTools.get(definition, "Properties.LaunchTemplateData", nil)
    if !launch_template_data.nil?
      resource = template["Resources"][name]['Properties']['LaunchTemplateData']

      JsonTools.transfer(definition['Properties']['LaunchTemplateData'], "KeyName", resource)
      JsonTools.transfer(definition['Properties']['LaunchTemplateData'], "BlockDeviceMappings", resource)
      JsonTools.transfer(definition['Properties']['LaunchTemplateData'], "InstanceMarketOptions", resource)
      JsonTools.transfer(definition['Properties']['LaunchTemplateData'], "Placement", resource)
      JsonTools.transfer(definition['Properties']['LaunchTemplateData'], "CreditSpecification.CpuCredits", resource)
      JsonTools.transfer(definition['Properties']['LaunchTemplateData'], "CpuOptions.CoreCount", resource)
      JsonTools.transfer(definition['Properties']['LaunchTemplateData'], "CpuOptions.ThreadsPerCore", resource)
      spot_alias = JsonTools.get(definition, "Properties.LaunchTemplateData.InstanceMarketOptions.SpotOptions.MaxPrice", nil)
      tenancy = JsonTools.get(definition, "Properties.LaunchTemplateData.Placement.Tenancy", nil)

      if !spot_alias.nil?
        spot_max_bid = Pricing::EC2.process_ec2_spot_price(
          spot_alias: spot_alias,
          platform: platform,
          instance_type: instance_type,
          tenancy: tenancy
        )
      end

      if !spot_max_bid.nil?
        resource["InstanceMarketOptions"]["SpotOptions"]["MaxPrice"] = spot_max_bid
      end
    end
  end
end
