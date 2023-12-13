# Module build CloudFormation AWS::StepFunctions::StateMachine
module StepFunctionsStateMachineBuilder
  # Generate CLoudFormation CustomResource for AWS::StepFunction::StateMachine
  # @param template [Hash] Reference to a template
  # @param definitions [Hash] State machine definition
  # @param resources [Hash] List of resources to be inserted into the function definition
  # @param role_arn [String] Role arn id to the used for execution
  def _process_step_functions_state_machine(
    template:,
    definitions:,
    resources:,
    role_arn:
  )

    name, definition = definitions.first
    definition_string = JsonTools.get(definition, 'Properties.DefinitionString')
    definition_string = definition_string.to_json unless definition_string.is_a? String

    # Substitute resource names into the state machine definition
    unless resources.nil? || resources.empty?
      definition_string = { 'Fn::Sub' => [definition_string, resources] }
    end

    template['Resources'][name] = {
      'Type' => 'AWS::StepFunctions::StateMachine',
      'Properties' => {
        'DefinitionString' => definition_string,
        'RoleArn' => role_arn
      }
    }

    template['Outputs']["#{name}Arn"] = {
      'Description' => "#{name} StepFunction StateMachine ARN",
      'Value' => { 'Ref' => name }
    }

    template['Outputs']["#{name}Name"] = {
      'Description' => "#{name} StepFunction StateMachine Name",
      'Value' => { 'Fn::GetAtt' => [name, 'Name'] }
    }
  end
end
