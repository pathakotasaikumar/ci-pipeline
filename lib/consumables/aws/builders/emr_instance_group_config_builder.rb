require "util/json_tools"

module EmrInstanceGroupConfigBuilder
  def _process_emr_instance_group_configs(
    template: nil,
    instance_group_config_definitions: nil,
    cluster_name: nil,
    component_name: nil
  )

    instance_group_config_definitions.each do |name, definition|
      sections = Defaults.sections
      group_name = [
        sections[:ams],
        sections[:qda],
        sections[:as],
        sections[:ase],
        sections[:branch],
        sections[:build],
        component_name,
        name,
      ].join('-')[0..128]

      template["Resources"][name] = {
        "Type" => "AWS::EMR::InstanceGroupConfig",
        "Properties" => {
          "Name" => group_name,
          "JobFlowId" => { "Ref" => cluster_name },
        }
      }
      resource = template["Resources"][name]

      JsonTools.transfer(definition, "Properties.BidPrice", resource)
      JsonTools.transfer(definition, "Properties.Configurations", resource)
      JsonTools.transfer(definition, "Properties.EbsConfiguration", resource)
      JsonTools.transfer(definition, "Properties.InstanceCount", resource, 1)
      JsonTools.transfer(definition, "Properties.InstanceRole", resource, "TASK")
      JsonTools.transfer(definition, "Properties.InstanceType", resource, "m3.xlarge")
      JsonTools.transfer(definition, "Properties.Market", resource)

      template["Outputs"]["#{name}Id"] = {
        "Description" => "EMR instance group config id",
        "Value" => { "Ref" => name }
      }
    end
  end
end
