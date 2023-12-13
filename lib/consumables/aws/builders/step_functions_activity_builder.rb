# Module build CloudFormation AWS::StepFunctions:Activity
module StepFunctionsActivityBuilder
  # Generate template for AWS::StepFunctions::Activity resource
  # @param template [Hash] Reference to a template
  # @param component_name [String] Name of the target component
  # @param definitions [Hash] StepFunctions activity definitions
  def _process_step_functions_activity(
    template:,
    component_name:,
    definitions:
  )

    definitions.each do |name, definition|
      template["Resources"][name] = {
        "Type" => "AWS::StepFunctions::Activity",
        "Properties" => {
          "Name" => _unique_activity_name(
            component_name: component_name,
            activity_name: name
          )
        }
      }

      template["Outputs"]["#{name}Arn"] = {
        "Description" => "ARN for #{name} StepFunction Activity Arn",
        "Value" => { "Ref" => name }
      }

      template["Outputs"]["#{name}Name"] = {
        "Description" => "ARN for #{name} StepFunction Activity Name",
        "Value" => { "Fn::GetAtt" => [name, 'Name'] }
      }
    end
  end

  # Returns a unique activity name
  # @param component_name [String] target component
  # @param activity_name [String] Logical resource name assigned to the activity in template
  def _unique_activity_name(
    component_name:,
    activity_name:
  )
    sections = Defaults.sections
    [
      sections[:ams],
      sections[:qda],
      sections[:as],
      sections[:ase],
      sections[:branch],
      component_name,
      activity_name
    ].join('-').gsub(/[^a-zA-Z0-9\-]/, '-')[0..79]
  end
end
