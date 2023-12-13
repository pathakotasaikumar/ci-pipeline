require "util/json_tools"

module ElastiCacheReplicationGroupBuilder
  def _process_elasticache_replication_group(
    template: nil,
    component_name: nil,
    replication_group: nil,
    parameter_group_name: nil,
    subnet_group_name: nil,
    security_group_ids: []
  )
    name, definition = replication_group.first

    template["Resources"][name] = {
      "Type" => "AWS::ElastiCache::ReplicationGroup",
      "Properties" => {
        "CacheNodeType" => JsonTools.get(definition, "Properties.CacheNodeType", "cache.m3.medium"),
        "CacheSubnetGroupName" => { "Ref" => subnet_group_name },
        "Engine" => "redis",
        "NumCacheClusters" => JsonTools.get(definition, "Properties.NumCacheClusters", 2).to_i,
        "ReplicationGroupDescription" => Defaults.component_name_tag(component_name: component_name),
        "SecurityGroupIds" => security_group_ids,
      }
    }
    resource = template["Resources"][name]

    # Add optional properties
    JsonTools.transfer(definition, "Properties.AutomaticFailoverEnabled", resource, resource["Properties"]["NumCacheClusters"] > 1)
    JsonTools.transfer(definition, "Properties.EngineVersion", resource)
    JsonTools.transfer(definition, "Properties.NotificationTopicArn", resource)
    JsonTools.transfer(definition, "Properties.Port", resource)
    JsonTools.transfer(definition, "Properties.PreferredMaintenanceWindow", resource)
    JsonTools.transfer(definition, "Properties.SnapshotArns", resource)
    JsonTools.transfer(definition, "Properties.SnapshotRetentionLimit", resource)
    JsonTools.transfer(definition, "Properties.SnapshotWindow", resource)
    JsonTools.transfer(definition, "Properties.AtRestEncryptionEnabled", resource)
    JsonTools.transfer(definition, "Properties.TransitEncryptionEnabled", resource)

    # Set the cache parameter group name, if defined
    resource["Properties"]["CacheParameterGroupName"] = { "Ref" => parameter_group_name } unless parameter_group_name.nil?

    # Set outputs
    template["Outputs"]["#{name}Name"] = {
      "Description" => "Replication Group Name",
      "Value" => { "Ref" => name },
    }

    template["Outputs"]["#{name}PrimaryEndPointAddress"] = {
      "Description" => "Primary endpoint address",
      "Value" => { "Fn::GetAtt" => [name, "PrimaryEndPoint.Address"] },
    }

    template["Outputs"]["#{name}PrimaryEndPointPort"] = {
      "Description" => "Primary endpoint port",
      "Value" => { "Fn::GetAtt" => [name, "PrimaryEndPoint.Port"] },
    }

    template["Outputs"]["#{name}ReadEndPointAddresses"] = {
      "Description" => "Read endpoint addresses",
      "Value" => { "Fn::Join" => [",", { "Fn::GetAtt" => [name, "ReadEndPoint.Addresses.List"] }] },
    }

    template["Outputs"]["#{name}ReadEndPointPorts"] = {
      "Description" => "Read endpoint ports",
      "Value" => { "Fn::Join" => [",", { "Fn::GetAtt" => [name, "ReadEndPoint.Ports.List"] }] },
    }
  end
end
