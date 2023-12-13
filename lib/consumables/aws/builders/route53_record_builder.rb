# Module responsible for constructing AWS::Route53::Resource
module Route53RecordBuilder
  # Builds CloudFormation resource
  # @param template [Hash] Reference to hash representation of CloudFormation template
  # @param record_name [String] Route53 record name
  # @param record_sets [Hash] Hash representations of Route53 record sets
  def _process_route53_records(
    template: nil,
    record_name: nil,
    record_sets: []
  )

    record_sets.each do |name, definition|
      Context.component.replace_variables(definition)
      template["Resources"][name] = {
        "Type" => "AWS::Route53::RecordSet",
        "Properties" => {
          "Name" => record_name || JsonTools.get(definition, "Properties.Name"),
          "Type" => JsonTools.get(definition, "Properties.Type"),
          "TTL" => JsonTools.get(definition, "Properties.TTL"),
          "ResourceRecords" => JsonTools.get(definition, "Properties.ResourceRecords")
        }
      }

      resource = template["Resources"][name]
      hosted_zone = Defaults.r53_hosted_zone
      hosted_zone += '.' unless hosted_zone.end_with?('.')
      resource["Properties"]["HostedZoneName"] = hosted_zone

      JsonTools.transfer(definition, "Properties.Comment", resource)
      JsonTools.transfer(definition, "Properties.Failover", resource)
      JsonTools.transfer(definition, "Properties.SetIdentifier", resource)
      JsonTools.transfer(definition, "Properties.AliasTarget", resource)
      JsonTools.transfer(definition, "Properties.GeoLocation", resource)
      JsonTools.transfer(definition, "Properties.Region", resource)
      JsonTools.transfer(definition, "Properties.Weight", resource)

      healthcheck = JsonTools.get(definition, "Properties.HealthCheckId", nil)
      unless healthcheck.nil?
        healthcheck = healthcheck.is_a?(String) ? { "Ref" => healthcheck } : healthcheck
        resource["Properties"]["HealthCheckId"] = healthcheck
      end
    end
  end
end
