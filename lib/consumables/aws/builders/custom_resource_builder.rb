# Module build CloudFormation custom resource

module CustomResourceBuilder
  # Generate CloudFormation CustomResource
  def _process_custom_resource(
    template: nil,
    resource_name: nil,
    dependency_name: nil,
    properties: nil
  )

    template["Resources"][resource_name] = {
      "Type" => "Custom::#{resource_name}",
      'DependsOn' => dependency_name,
      "Properties" => properties
    }
  end
end
