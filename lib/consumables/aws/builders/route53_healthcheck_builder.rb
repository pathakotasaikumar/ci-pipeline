# Module responsible for constructing AWS::Route53::Resource
module Route53HealthCheckBuilder
  # Builds Cloudformation resource
  # @param template [Hash] Reference to hash representation of CloudFormation template
  # @param healthchecks [Hash] Hash representations of Route53 healthchecks
  def _process_route53_healthcheck(
    template: nil,
    healthchecks: nil
  )

    healthchecks.each do |name, definition|
      Context.component.replace_variables(definition)
      template["Resources"][name] = {
        "Type" => "AWS::Route53::HealthCheck",
        "Properties" => {
          "HealthCheckConfig" => JsonTools.get(definition, "Properties.HealthCheckConfig")
        }
      }
      template["Outputs"]["#{name}HealthCheckId"] = {
        "Description" => "Route 53 Health Check ID",
        "Value" => { "Ref" => name }
      }
    end
  end
end
