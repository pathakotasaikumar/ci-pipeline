# Module buildss required to process Pipeline::EC2::ScheduledAction resource

require "consumables/aws/builders/pipeline_scheduled_action_builder"
require "util/json_tools"

module InstanceScheduledActionBuilder
  include PipelineScheduledActionBuilder

  # Builds CFN resources based on PipelineScheduledAction module
  #
  # @param template [Hash] - template definition carried into the module
  # @param scheduled_actions [Hash] - array of hashes describing scheduled actions.
  # @param execution_role_arn [String] - reference to existing IAM role to be used for action execution

  def _process_ec2_scheduled_actions(
    template:,
    scheduled_actions:,
    execution_role_arn:
  )

    _process_pipeline_scheduled_actions(
      template: template,
      action_name: "InstanceScheduling",
      code: "#{__dir__}/../aws_instance/instance_scheduling.py",
      scheduled_actions: scheduled_actions,
      execution_role_arn: execution_role_arn
    )
  end

  # Parse definitions for Pipeline::EC2::ScheduledAction
  # @param definitions [Array] - Load hash containing definition for Pipeline::EC2::ScheduledAction resource
  # @return [Hash] - Named map of inputs and cron schedules associated with the instance name

  def _parse_ec2_scheduled_actions(definitions:, instance_name:)
    scheduled_actions = {}
    # parse EC2 scheduled action
    definitions.each do |name, definition|
      action = JsonTools.get(definition, "Properties.Action", nil).downcase
      schedule_expression = JsonTools.get(definition, "Properties.Recurrence", nil)

      # Validate cron expression according to supported syntax
      # http://docs.aws.amazon.com/AmazonCloudWatch/latest/events/ScheduledEvents.html
      cron_regex = /^([0-9,\-*\/]+) ([0-9,\-*\/]+) ([0-9,\-*?\/LW]+) ([0-9A-Z,\-*?\/]+) ([1-7A-Z,\-*?\/L]+)$/
      raise "Unknown schedule expression" unless schedule_expression.match(cron_regex)
      raise "Must specify '?' for either - day-of-month or day-of-week" unless (Regexp.last_match[3] == "?") ^ (Regexp.last_match[5] == "?")

      unless %w(stop start).include?(action)
        raise "Action is a required property for Pipeline::EC2::ScheduledAction" \
              " resource and it must be of the values stop or start"
      end

      scheduled_actions[name] = {
        # Note: the 6th field (Year) is defaulted to * to align with AWS::Autoscaling::ScheduledActions
        "schedule_expression" => "cron(#{schedule_expression} *)",
        "inputs" => {
          "InstanceId" => { "Ref" => instance_name },
          "Action" => action
        }
      }
    end
    scheduled_actions
  end

  # Return security rules required for EC2 Scheduled Action Execution
  #
  # @param component_name[String] used to target component specific roles
  # @return [Array] SecurityRules (see #SecurityRuleBuilder)
  def _ec2_scheduled_action_security_rules(component_name:, instance_name: nil)
    instance_id = Context.component.variable(component_name, "#{instance_name}Id", nil)
    security_rules = []

    unless instance_id.nil?

      security_rules += [

        # Allow Stopping and Starting of the instance
        IamSecurityRule.new(
          roles: "#{component_name}.Ec2ScheduledActionExecutionRole",
          actions: %w(
            ec2:StopInstances
            ec2:StartInstances
          ),
          resources: %W(
            arn:aws:ec2:#{Context.environment.region}:#{Context.environment.account_id}:instance/#{instance_id}
          )
        ),
        IamSecurityRule.new(
          roles: "#{component_name}.Ec2ScheduledActionExecutionRole",
          actions: %w(
            logs:CreateLogStream
            logs:PutLogEvents
          ),
          resources: %w(
            arn:aws:logs:*:*:*
          )
        ),
        # allow lambda to use app KMS key in order to start an instance with CMK encrypted volumes
        # QCP-2701 and QCP-2761
        IamSecurityRule.new(
          roles: "#{component_name}.Ec2ScheduledActionExecutionRole",
          actions: %w(
            kms:CreateGrant
          ),
          resources: %W(
            #{Context.kms.secrets_key_arn}
          )
        )
      ]
    end

    return security_rules
  end

  # Return security items required for EC2 Scheduled Action Execution
  #
  # @param component_name [String] - Reference to component/stack for the action to be attached
  # @return [Array] Security items

  def _ec2_scheduled_action_security_items(component_name:)
    [
      {
        "Name" => "Ec2ScheduledActionExecutionRole",
        "Type" => "Role",
        "Component" => component_name,
        "Service" => "lambda.amazonaws.com"
      }
    ]
  end
end
