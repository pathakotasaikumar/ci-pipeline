# Helper module used to generate scheduled actions based on
# AWS::Events::Rule and AWS::Lambda::Function resources

require "consumables/aws/builders/lambda_function_builder"
require "consumables/aws/builders/lambda_permission_builder"
require "consumables/aws/builders/events_rule_builder"
require "util/user_data"
require "util/json_tools"

module PipelineScheduledActionBuilder
  include EventsRuleBuilder
  include LambdaFunctionBuilder
  include LambdaPermissionBuilder

  # Builds CFN resources based on PipelineScheduledAction module
  #
  # @param template [Hash] template definition carried into the module
  # @param action_name [String] name/label for scheduled action ('EMRScaling')
  # @param code [String/Hash] reference to a file to be used as Lambda inline code or a hash with S3 bucket/key
  # @param execution_role_arn [String] reference to existing IAM role to be used for Lambda execution
  # @param scheduled_actions [Hash] definitions describing scheduled actions.
  def _process_pipeline_scheduled_actions(
    template:,
    action_name:,
    code:,
    execution_role_arn:,
    scheduled_actions:
  )

    # Create lambda function definition to be used by events
    _process_lambda_function(
      template: template,
      role: execution_role_arn,
      function_definition: {
        action_name => {
          "Type" => "AWS::Lambda::Function",
          "Properties" => {
            "Handler" => "index.handler",
            "Runtime" => "python3.9",
            "Timeout" => "300",
            "Code" => code
          }
        }
      }
    )

    # Generate one event + lambda permission per scheduled action definition
    scheduled_actions.each do |name, action_definition|
      _process_events_rule(
        template: template,
        definitions: {
          name => {
            'Type' => 'AWS::Events::Rule',
            'Properties' => {
              'ScheduleExpression' => action_definition['schedule_expression'],
              'Targets' => [
                {
                  'Arn' => { 'Fn::GetAtt' => [action_name, 'Arn'] },
                  'Id' => action_name,
                  'Input' => { 'Fn::Join' => ['', ['{', JsonTools.hash_to_cfn_join(action_definition['inputs']), '}']] }
                }
              ]
            }
          }
        }
      )

      _process_lambda_permission(
        template: template,
        permissions: {
          "#{name}ScheduledEventPermission" => {
            "Properties" => {
              "Action" => "lambda:InvokeFunction",
              "FunctionName" => { "Fn::GetAtt" => [action_name, "Arn"] },
              "Principal" => "events.amazonaws.com",
              "SourceArn" => { "Fn::GetAtt" => [name, "Arn"] }
            }
          }
        }
      )
    end
  end
end
