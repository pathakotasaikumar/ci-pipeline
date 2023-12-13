# Helper module used to generate a state machine based on
# AWS::Events::Rule and AWS::Lambda::Function resources

require_relative 'lambda_function_builder'
require_relative 'events_rule_builder'
require_relative 'step_functions_state_machine_builder'
require 'util/user_data'
require 'util/json_tools'

module PipelineScheduledWorkflowBuilder
  include EventsRuleBuilder
  include LambdaFunctionBuilder
  include StepFunctionsStateMachineBuilder

  # Builds CFN resources based on PipelineScheduledAction module
  #
  # @param template [Hash] template definition carried into the module
  # @param lambda_function_definitions [String]
  # @param events_role_arn [String] Role to be used for the CW rule
  # @param execution_role_arn [String] IAM role ID for the execution role
  # @param scheduled_actions [Hash] Schedule actions definitions
  # @param state_machine_definition [Hash] Hash representation of the state machine definition
  # @param security_group_ids [Array]
  def _process_pipeline_scheduled_workflow(
    template:,
    lambda_function_definitions:,
    events_role_arn:,
    execution_role_arn:,
    scheduled_actions:,
    state_machine_definition:,
    security_group_ids:
  )

    state_machine_name = state_machine_definition.keys.first

    resources = {}

    # @todo: move lambda functions to S3
    # Create lambda function definition to be used by events
    lambda_function_definitions.each do |name, definition|
      _process_lambda_function(
        template: template,
        role: execution_role_arn,
        function_definition: { name => definition },
        security_group_ids: security_group_ids
      )

      resources[name] = { 'Fn::GetAtt' => [name, 'Arn'] }
    end

    _process_step_functions_state_machine(
      template: template,
      role_arn: _states_execution_role,
      definitions: state_machine_definition,
      resources: resources
    )

    # Generate one event + lambda permission per scheduled action definition
    # format input hash as a valid JSON string
    scheduled_actions.each do |name, definition|
      _process_events_rule(
        template: template,
        definitions: {
          name => {
            'Type' => 'AWS::Events::Rule',
            'Properties' => {
              'ScheduleExpression' => definition['schedule_expression'],
              'Targets' => [
                {
                  'Arn' => { 'Ref' => state_machine_name },
                  'Id' => state_machine_name,
                  'Input' => definition['inputs'],
                  'RoleArn' => events_role_arn
                }
              ]
            }
          }
        }
      )
    end
  end

  private

  # Returns StepFunctions region specific service role
  # @return [String] Region specific StepFunctions service role
  def _states_execution_role
    %W(
      arn:aws:iam:
      #{Context.environment.account_id}
      role/service-role/StatesExecutionRole-#{Context.environment.region}
    ).join(':')
  end
end
