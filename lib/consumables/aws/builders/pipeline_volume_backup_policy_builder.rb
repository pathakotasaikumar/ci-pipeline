require_relative 'pipeline_backup_policy_builder'
require 'util/user_data'

module PipelineVolumeBackupPolicyBuilder
  include PipelineBackupPolicyBuilder

  # BackupPolicy resources
  # @param definitions [Hash] - Hash containing definitions
  # @param resource_id [Object] - Reference to a resource (string or Ref)
  # @param component_name [String] - name of the calling component
  def _parse_volume_backup_policy(
    definitions:,
    resource_id:,
    component_name:
  )

    backup_policies = {}

    definitions.each do |name, definition|
      targets = JsonTools.get(definition, 'Properties.CopyTargets', [])

      schedule_expression = JsonTools.get(definition, 'Properties.Recurrence')
      _validate_recurrence(schedule_expression, targets.any?)

      # add origin to the list of targets
      targets << {
        'Target' => JsonTools.get(definition, 'Properties.Target', '@origin'),
        'RetentionPeriod' => JsonTools.get(definition, 'Properties.RetentionPeriod')
      }

      # validate target alias and retention period
      targets.map! do |target|
        {
          'account_alias' => _validate_account_alias(target['Target']),
          'retention_period' => target['RetentionPeriod']
        }
      end

      # Note: the 6th field (Year) is defaulted to * to align with AWS::Autoscaling::ScheduledActions
      inputs = {
        'type' => 'aws/volume',
        'source' => {
          'id' => '${resource_id}',
          'consistent' => JsonTools.get(definition, 'Properties.Consistent', 'false'),
          'target_alias' => _validate_account_alias('@origin'),
          'account_id' => Context.environment.account_id,
          'region' => Context.environment.region,
          'name' => Defaults.build_specific_id(component_name).join("-"),
          'key_alias' => Defaults.kms_secrets_key_alias
        },
        'targets' => targets,
        'tags' => _tags(component_name)
      }

      backup_policies[name] = {
        'schedule_expression' => "cron(#{schedule_expression} *)",
        'inputs' => { 'Fn::Sub' => [inputs.to_json, { 'resource_id' => resource_id }] }
      }
    end

    backup_policies
  end
end
