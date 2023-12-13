# Module buildss required to process Pipeline::DynamoDB::ScheduledAction resource

require "consumables/aws/builders/pipeline_scheduled_action_builder"
require "util/json_tools"

module DynamoDBScheduledActionBuilder
  include PipelineScheduledActionBuilder

  # Builds CFN resources based on PipelineScheduledAction module
  #
  # @param template [Hash] - template definition carried into the module
  # @param scheduled_actions [Hash] - array of hashes describing scheduled actions.
  # @param execution_role_arn [String] - reference to existing IAM role to be used for action execution

  ScriptsDir = "#{__dir__}/../dynamodb".freeze

  def _process_dynamodb_scheduled_actions(
    template:,
    scheduled_actions:,
    execution_role_arn:
  )

    _process_pipeline_scheduled_actions(
      template: template,
      action_name: "DynamoDBScaling",
      code: File.join(ScriptsDir, 'common', 'ScalingFunction.py'),
      scheduled_actions: scheduled_actions,
      execution_role_arn: execution_role_arn
    )
  end

  # Parse definitions for Pipeline::DynamoDB::ScheduledAction
  # @param definitions [Array] - Load hash containing definition for Pipeline::DynamoDB::ScheduledAction resource
  # @return [Hash] - Named map of inputs and cron schedules

  def _parse_dynamodb_scheduled_action(definitions: nil)
    scheduled_actions = {}
    # parse DynamoDB scheduled action
    definitions.each do |name, definition|
      table_name = JsonTools.get(definition, "Properties.TableName", nil)
      read_capacity = JsonTools.get(definition, "Properties.SetReadCapacity", nil)
      write_capacity = JsonTools.get(definition, "Properties.SetWriteCapacity", nil)
      schedule_expression = JsonTools.get(definition, "Properties.Recurrence", nil)

      # Validate cron expression according to supported syntax
      # http://docs.aws.amazon.com/AmazonCloudWatch/latest/events/ScheduledEvents.html
      cron_regex = /^([0-9,\-*\/]+) ([0-9,\-*\/]+) ([0-9,\-*?\/LW]+) ([0-9A-Z,\-*?\/]+) ([1-7A-Z,\-*?\/L]+)$/
      raise "Unknown schedule expression" unless schedule_expression.match(cron_regex)
      raise "Must specify '?' for either - day-of-month or day-of-week" unless (Regexp.last_match[3] == "?") ^ (Regexp.last_match[5] == "?")
      raise "Invalid read capacity count - #{read_capacity}" unless read_capacity.is_a? Integer
      raise "Invalid write capacity count - #{write_capacity}" unless write_capacity.is_a? Integer

      if table_name.nil? || table_name.empty?
        raise "TableName is a required property for Pipeline::DynamoDB::ScheduledAction resource"
      end

      scheduled_actions[name] = {
        # Note: the 6th field (Year) is defaulted to * to align with AWS::Autoscaling::ScheduledActions
        "schedule_expression" => "cron(#{schedule_expression} *)",
        "inputs" => {
          "TableName" => { "Ref" => table_name },
          "SetReadCapacity" => read_capacity,
          "SetWriteCapacity" => write_capacity,
        }
      }
    end
    scheduled_actions
  end

  # Return security rules required for DynamoDB Scheduled Action Execution
  #
  # @param component_name[String] used to target component specific roles
  # @return [Array] SecurityRules (see #SecurityRuleBuilder)
  def _dynamodb_scheduled_action_security_rules(component_name:)
    [
      # Allow attachment of volumes
      IamSecurityRule.new(
        roles: "#{component_name}.DynamoDBScalingExecutionRole",
        actions: %w(
          dynamodb:UpdateTable
          dynamodb:DescribeTable
        ),
        resources: %w(*)
      ),
      IamSecurityRule.new(
        roles: "#{component_name}.DynamoDBScalingExecutionRole",
        actions: %w(
          logs:CreateLogStream
          logs:PutLogEvents
        ),
        resources: %w(arn:aws:logs:*:*:*)
      )
    ]
  end

  # Return security items required for DynamoDB Scheduled Action Execution
  #
  # @param component_name [String] - Reference to component/stack for the action to be attached
  # @return [Array] Security items

  def _dynamodb_scheduled_action_security_items(component_name:)
    [
      {
        "Name" => "DynamoDBScalingExecutionRole",
        "Type" => "Role",
        "Component" => component_name,
        "Service" => "lambda.amazonaws.com"
      }
    ]
  end
end
