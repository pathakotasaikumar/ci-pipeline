# Module responsible for construction Pipeline::SNS::Factory template
require "consumables/aws/builders/lambda_function_builder"
require "consumables/aws/builders/custom_resource_builder"
require_relative "types/security_rule"

module SnsFactoryBuilder
  include LambdaFunctionBuilder
  include CustomResourceBuilder

  # Generates IAM security rules required for execution of the custom resource lambda
  # @param component_name [String] - name of the component to attach delete topic resources to
  # @param execution_role_name [String] - Reference to AWS IAM role name (for Lambda execution)
  # @param prefix_arn [String] SNS Factory Topic Prefix Arn
  def _delete_topics_lambda_security_rules(
    component_name:,
    execution_role_name:,
    prefix_arn:
  )

    [
      # Allow deletion of topics created by sns factory
      IamSecurityRule.new(
        roles: "#{component_name}.#{execution_role_name}",
        actions: %w(
          sns:DeleteTopic
        ),
        resources: "#{prefix_arn}*"
      ),
      # Allow List Topics
      IamSecurityRule.new(
        roles: "#{component_name}.#{execution_role_name}",
        actions: %w(
          sns:ListTopics
        ),
        resources: '*'
      ),
      IamSecurityRule.new(
        roles: "#{component_name}.#{execution_role_name}",
        actions: %w(
          logs:CreateLogStream
          logs:PutLogEvents
        ),
        resources: %w(arn:aws:logs:*:*:*)
      )
    ]
  end

  # @param template [Hash] reference to template carried into the module
  # @param prefix [String] SNS Factory Topic Prefix
  # @param component_name [String] - name of the component to attach delete topic resources to
  # @param execution_role_name [String] - Reference to AWS IAM role name (for Lambda execution)
  def _process_sns_factory(
    template:,
    prefix:,
    execution_role_arn:
  )

    filepath = "#{__dir__}/../aws_sns_factory/lambda_delete_topics.py"

    # Create lambda function definition for custom custom resource
    _process_lambda_function(
      template: template,
      role: execution_role_arn,
      function_definition: {
        'SNSFactoryCustomResourceLambda' => {
          'Type' => 'AWS::Lambda::Function',
          'Properties' => {
            'Handler' => 'index.lambda_handler',
            'Runtime' => 'python3.9',
            'Timeout' => '300',
            'Code' => filepath
          }
        }
      }
    )

    _process_custom_resource(
      template: template,
      resource_name: 'InvokeLambda',
      dependency_name: 'SNSFactoryCustomResourceLambda',
      properties: {
        'ServiceToken' => {
          'Fn::GetAtt' => ['SNSFactoryCustomResourceLambda', 'Arn']
        },
        'Region' => [
          {
            'Ref' => 'AWS::Region'
          }
        ],
        'TopicPrefix' => prefix
      }
    )
    return template
  end
end
