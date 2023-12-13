require "util/json_tools"

module ElastiCacheParameterGroupBuilder
  def _process_elasticache_parameter_group(
    template: nil,
    parameter_group: nil
  )
    name, definition = parameter_group.first

    template["Resources"][name] = {
      "Type" => "AWS::ElastiCache::ParameterGroup",
      "Properties" => {
        "CacheParameterGroupFamily" => JsonTools.get(definition, "Properties.CacheParameterGroupFamily"),
        "Description" => "ElastiCache parameter group #{name}",
      }
    }
    resource = template["Resources"][name]

    JsonTools.transfer(definition, "Properties.Properties", resource)

    # Set outputs
    template["Outputs"]["#{name}Name"] = {
      "Description" => "ElastiCache Parameter Group Name",
      "Value" => { "Ref" => name },
    }
  end
end
