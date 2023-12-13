# Module buildss required to process Pipeline::EMR::ScheduledAction resource

require "consumables/aws/builders/pipeline_scheduled_action_builder"
require "util/json_tools"

module EMRScheduledActionBuilder
  include PipelineScheduledActionBuilder

  # Builds CFN resources based on PipelineScheduledAction module
  #
  # @param template [Hash] - template definition carried into the module
  # @param scheduled_actions [Hash] - array of hashes describing scheduled actions.
  # @param execution_role_arn [String] - reference to existing IAM role to be used for action execution

  def _process_emr_scheduled_actions(
    template: nil,
    scheduled_actions: nil,
    execution_role_arn: nil
  )

    _process_pipeline_scheduled_actions(
      template: template,
      action_name: "EMRScaling",
      code: "#{__dir__}/../emr/emr_scaling.py",
      scheduled_actions: scheduled_actions,
      execution_role_arn: execution_role_arn,
    )
  end

  # Parse definitions for Pipeline::EMR::ScheduledAction
  #
  # @param cluster [String] - Cluster ID for for target action. Can be supplied as CFN reference
  # @param definitions [Array] - Load hash containing definition for Pipeline::EMR::ScheduledAction resource

  def _parse_emr_scheduled_action(cluster: nil, definitions: nil)
    scheduled_actions = {}
    # parse EMR scheduled action
    definitions.each do |name, definition|
      instance_group = definition["Properties"]["InstanceGroup"]
      instance_count = definition["Properties"]["InstanceCount"]
      schedule_expression = definition["Properties"]["Recurrence"]

      # Validate cron expression according to supported syntax
      # http://docs.aws.amazon.com/AmazonCloudWatch/latest/events/ScheduledEvents.html
      cron_regex = /^([0-9,\-*\/]+) ([0-9,\-*\/]+) ([0-9,\-*?\/LW]+) ([0-9A-Z,\-*?\/]+) ([1-7A-Z,\-*?\/L]+)$/
      raise "Unknown schedule expression" unless schedule_expression.match(cron_regex)
      raise "Must specify '?' for either - day-of-month or day-of-week" unless (Regexp.last_match[3] == "?") ^ (Regexp.last_match[5] == "?")
      raise "Invalid instance count - #{instance_count}" unless instance_count.to_s.match(/\d+/)

      if instance_group.downcase == "core"
        instance_group_id = "CORE"
        raise "Unable to set CORE instance group to 0" if instance_count == 0
      else
        instance_group_id = { "Ref" => instance_group }
      end

      scheduled_actions[name] = {
        # Note: the 6th field (Year) is defaulted to * to align with AWS::Autoscaling::ScheduledActions
        "schedule_expression" => "cron(#{schedule_expression} *)",
        "inputs" => {
          "cluster" => cluster,
          "instance_group" => instance_group_id,
          "instance_count" => instance_count,
        }
      }
    end
    return scheduled_actions
  end

  # Return security rules required for EMR Scheduled Action Execution
  #
  # @param component_name[String] used to target component specific roles
  # @return [Array] SecurityRules (see #SecurityRuleBuilder)
  def _emr_scheduled_action_security_rules(component_name: nil)
    [
      # Allow attachment of volumes
      IamSecurityRule.new(
        roles: "#{component_name}.EMRScalingExecutionRole",
        actions: %w(
          elasticmapreduce:ModifyInstanceGroups
          elasticmapreduce:ListInstanceGroups
        ),
        resources: %w(*)
      ),
      IamSecurityRule.new(
        roles: "#{component_name}.EMRScalingExecutionRole",
        actions: %w(
          logs:CreateLogStream
          logs:PutLogEvents
        ),
        resources: %w(arn:aws:logs:*:*:*)
      )
    ]
  end

  # Return security items required for EMR Scheduled Action Execution
  #
  # @param component_name [String] - Reference to component/stack for the action to be attached
  # @return [Array] Security items

  def _emr_scheduled_action_security_items(component_name: nil)
    [
      {
        "Name" => "EMRScalingExecutionRole",
        "Type" => "Role",
        "Component" => component_name,
        "Service" => "lambda.amazonaws.com"
      }
    ]
  end
end
