# Module builds AWS resources for execution of autoscaling lifecycle hook
# based on lambda function subscription to SNS topic notification
# lifecycle hook notification metadata is used to pass parameters to lambda functions

require_relative "lambda_function_builder"
require_relative "sns_topic_builder"
require_relative "lifecycle_hook_builder"
require_relative "lambda_permission_builder"

module PipelineAutoscalingActionBuilder
  include LambdaFunctionBuilder
  include LambdaPermissionBuilder
  include LifecycleHookBuilder
  include SnsTopicBuilder

  # @param template [Hash] reference to hash to be used for CF template generation
  # @param action_name [String] stack uniq action_name to be used for all related CF resources
  # @param autoscaling_group_name [String] name of the autoscaling group to attach lifecycle hook to
  # @param notification_metadata [String] pass metadata as a string to the executor
  # @param execution_role_arn [String] arn for a role to be used for Lambda execution
  # @param notification_role_arn [String] arn for a role to be used for SNS notifications
  # @param lambda_code [String] path to local filename or an {S3Bucket,S3Key} hash
  def _process_pipeline_autoscaling_action(
    template:,
    action_name:,
    autoscaling_group_name:,
    execution_role_arn:,
    notification_role_arn:,
    notification_metadata:,
    lambda_code:,
    heartbeat_timeout: 60,
    security_group_ids: nil,
    lifecycle_transition: "autoscaling:EC2_INSTANCE_LAUNCHING",
    handler_name: "index.handler"
  )

    _process_lambda_function(
      template: template,
      role: execution_role_arn,
      security_group_ids: security_group_ids,
      function_definition: {
        "#{action_name}Lambda" => {
          "Properties" => {
            "Handler" => handler_name,
            "Runtime" => "python3.9",
            "Timeout" => 300,
            "Code" => lambda_code
          }
        }
      }
    )

    _process_sns_topic(
      template: template,
      definitions: {
        "#{action_name}Topic" => {
          'Type' => 'AWS::SNS::Topic',
          'Properties' => {
            'Subscriptions' => [{
              'Endpoint' => { 'Fn::GetAtt' => ["#{action_name}Lambda", "Arn"] },
              'Protocol' => 'lambda'
            }]
          }
        }
      }
    )

    lifecycle_hooks = {
      "#{action_name}LifecycleHook" => {
        "Properties" => {
          "DefaultResult" => "ABANDON",
          "HeartbeatTimeout" => heartbeat_timeout,
          "LifecycleTransition" => lifecycle_transition,
          "NotificationTargetARN" => { "Ref" => "#{action_name}Topic" },
          "NotificationMetadata" => notification_metadata,
        }
      }
    }

    _process_lifecycle_hooks(
      template: template,
      lifecycle_hooks: lifecycle_hooks,
      autoscaling_group_name: autoscaling_group_name,
      role_arn: notification_role_arn,
    )

    _process_lambda_permission(
      template: template,
      permissions: {
        "#{action_name}LambdaPermission" => {
          "Properties" => {
            "Action" => "lambda:InvokeFunction",
            "FunctionName" => { "Fn::GetAtt" => ["#{action_name}Lambda", "Arn"] },
            "Principal" => "sns.amazonaws.com",
            "SourceArn" => { "Ref" => "#{action_name}Topic" }
          }
        }
      }
    )
  end
end
