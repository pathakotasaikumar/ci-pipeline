require "util/json_tools"
require "pricing/ec2"

# Module is responsible for generating autoscaling group CloudFormation resource
# Create WaitCondition companion resource for capturing CFN signals from deployed instances
module AutoscalingGroupBuilder
  # Generate AWS::AutoScalingGroup resource and companion AWS::CloudFormation::WaitCondition
  # Adds reference to the wait condition in Autoscaling Group resource metadata
  # @param template [Hash] CloudFormation template passed in as reference
  # @param autoscaling_group_definition [Hash] AutoscalingGroup resource parsed from YAML definition
  # @param load_balancer_name [String] Logical name for associated LoadBalancer resource
  # @param wait_condition_name [String] Logical name for a WaitCondition resource for signals
  def _process_autoscaling_group(
    template: nil,
    platform: nil,
    autoscaling_group_definition: nil,
    load_balancer_name: nil,
    launch_configuration_name: nil,
    launch_template_name: nil,
    wait_condition_name: nil
  )
    name, definition = autoscaling_group_definition.first
    Context.component.replace_variables(definition)

    # If we are not supplying wait_condition_name then start at 0
    blank = wait_condition_name.nil?

    # Take values from params or default to 1/1
    min_size = blank ? 0 : JsonTools.get(definition, "Properties.MinSize", 1)
    max_size = blank ? 0 : JsonTools.get(definition, "Properties.MaxSize", 1)
    desired_capacity = blank ? nil : JsonTools.get(definition, "Properties.DesiredCapacity", nil)

    # Replace existing wait condition with a new wait condition
    previous_wait_condition_name = JsonTools.get(
      template, "Resources.#{name}.Metadata.WAIT_CONDITION", nil
    )

    template["Resources"].delete(previous_wait_condition_name)
    wait_condition_name ||= "Wait#{Time.now.strftime('%s')}"

    template["Resources"][wait_condition_name] = {
      "Type" => "AWS::CloudFormation::WaitCondition",
      "Properties" => {},
      "CreationPolicy" => {
        "ResourceSignal" => {
          "Count" => desired_capacity || min_size,
          "Timeout" => JsonTools.get(
            definition, "CreationPolicy.ResourceSignal.Timeout", "PT45M"
          )
        }
      }
    }

    # Create the AutoScalingGroup resource
    subnet_alias = JsonTools.get(definition, "Properties.VPCZoneIdentifier", "@private")
    subnet_ids = Context.environment.subnet_ids(subnet_alias)
    health_check_type = if load_balancer_name.nil? && JsonTools.get(definition, "Properties.TargetGroupARNs", nil).nil?
                          'EC2'
                        else
                          'ELB'
                        end
    template["Resources"][name] = {
      "Type" => "AWS::AutoScaling::AutoScalingGroup",
      "Metadata" => {
        "WAIT_CONDITION" => wait_condition_name
      },
      "Properties" => {
        "HealthCheckGracePeriod" => JsonTools.get(definition, "Properties.HealthCheckGracePeriod", 600),
        "HealthCheckType" => JsonTools.get(definition, "Properties.HealthCheckType", health_check_type),
        "MinSize" => min_size,
        "MaxSize" => max_size,
        "DesiredCapacity" => desired_capacity || min_size,
        "VPCZoneIdentifier" => subnet_ids,
        "MetricsCollection" => [{ "Granularity" => "1Minute" }],
      }
    }

    resource = template["Resources"][name]
    JsonTools.transfer(definition, "Properties.Cooldown", resource)
    JsonTools.transfer(definition, "Properties.TargetGroupARNs", resource)
    JsonTools.transfer(definition, "Properties.NewInstancesProtectedFromScaleIn", resource)
    resource["Properties"]["LoadBalancerNames"] = [{ "Ref" => load_balancer_name }] unless load_balancer_name.nil?

    # Getting the Launch definition base on launch_data_type and adding to template hash
    # Should be either LaunchConfiguration or LaunchTemplate

    launch_resource = _process_launch_data_type(
      definition: definition,
      launch_configuration_name: launch_configuration_name,
      launch_template_name: launch_template_name
    )
    template["Resources"][name]["Properties"].merge!(launch_resource)

    mixedinstance_policy = JsonTools.get(definition, "Properties.MixedInstancesPolicy", nil)
    if !mixedinstance_policy.nil?
      if !blank then
        JsonTools.transfer(definition, "Properties.MixedInstancesPolicy.InstancesDistribution.OnDemandBaseCapacity", resource)
      end
      JsonTools.transfer(definition, "Properties.MixedInstancesPolicy.InstancesDistribution.OnDemandAllocationStrategy", resource)
      JsonTools.transfer(definition, "Properties.MixedInstancesPolicy.InstancesDistribution.OnDemandPercentageAboveBaseCapacity", resource)
      JsonTools.transfer(definition, "Properties.MixedInstancesPolicy.InstancesDistribution.SpotAllocationStrategy", resource)
      JsonTools.transfer(definition, "Properties.MixedInstancesPolicy.InstancesDistribution.SpotInstancePools", resource)
      JsonTools.transfer(definition, "Properties.MixedInstancesPolicy.InstancesDistribution.SpotMaxPrice", resource)

      spot_alias = JsonTools.get(definition, "Properties.MixedInstancesPolicy.InstancesDistribution.SpotMaxPrice", nil)
      instance_type_override_list = JsonTools.get(definition, "Properties.MixedInstancesPolicy.LaunchTemplate.Overrides", [])
      if !spot_alias.nil?
        spot_max_bid = Pricing::EC2.process_ec2_spot_price(
          spot_alias: spot_alias,
          platform: platform,
          instance_type: instance_type_override_list[0]["InstanceType"],
          tenancy: "dedicated"
        )
      end

      if !spot_max_bid.nil?
        resource["Properties"]["MixedInstancesPolicy"]["InstancesDistribution"]["SpotMaxPrice"] = spot_max_bid
      end
    end

    # Set outputs
    template["Outputs"]["#{name}Name"] = {
      "Description" => "Autoscaling group name",
      "Value" => { "Ref" => name }
    }
  end

  def _process_launch_data_type(
    definition:,
    launch_configuration_name: nil,
    launch_template_name: nil
  )
    if !launch_configuration_name.nil?
      {
        "LaunchConfigurationName" => {
          "Ref" => "#{launch_configuration_name}"
        }
      }
    elsif !launch_template_name.nil?
      mixedinstance_policy = JsonTools.get(definition, "Properties.MixedInstancesPolicy", nil)
      if !mixedinstance_policy.nil?
        {
          "MixedInstancesPolicy" => {
            "LaunchTemplate" => {
              "LaunchTemplateSpecification" => {
                "LaunchTemplateId" => {
                  "Ref" => "#{launch_template_name}"
                },
                "Version" => "1"
              },
              "Overrides" => JsonTools.get(definition, "Properties.MixedInstancesPolicy.LaunchTemplate.Overrides", [])
            }
          }
        }
      else
        {
          "LaunchTemplate" => {
            "LaunchTemplateId" => {
              "Ref" => "#{launch_template_name}"
            },
            "Version" => '1'
          }
        }
      end
    else
      raise "Launch Configuration or Launch template not found in definition "
    end
  end
end
