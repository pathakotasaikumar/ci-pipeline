require "util/json_tools"

module ElastiCacheSubnetGroupBuilder
  def _process_elasticache_subnet_group(
    template: nil,
    subnet_group: nil
  )
    name, definition = subnet_group.first

    subnets = JsonTools.get(definition, "Properties.SubnetIds", "@private")
    subnet_ids = []
    Array(subnets).each do |subnet|
      subnet_ids += Context.environment.subnet_ids(subnet)
    end

    template["Resources"][name] = {
      "Type" => "AWS::ElastiCache::SubnetGroup",
      "Properties" => {
        "Description" => "Subnet group #{name}",
        "SubnetIds" => subnet_ids,
      }
    }
  end
end
