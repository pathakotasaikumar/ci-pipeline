require_relative 'lambda_function_builder'
require_relative 'lambda_permission_builder'
require_relative 'events_rule_builder'
require 'util/user_data'

# Module provides a builder method and associated helper functions for constructing
# a generic Pipeline backup policy.
# Note: this module should be mixed into a specialised backup policy modules
#   such as Pipeline::Volume::BackupPolicy
module PipelineBackupPolicyBuilder
  include EventsRuleBuilder
  include LambdaFunctionBuilder
  include LambdaPermissionBuilder

  BackupPolicyBuilderDir = "#{__dir__}/../backups".freeze

  # Builds CFN resources based on PipelineScheduledAction module
  #
  # @param template [Hash] - template definition carried into the module
  # @param backup_policy [Hash] - array of hashes describing scheduled actions.
  def _process_backup_policy(
    template:,
    backup_policy:
  )

    engine_topic_name = Defaults.backup_engine_topic_name
    raise "Unable to resolve engine sns topic arn from #{engine_topic_name}" if engine_topic_name.blank?

    # Generate one event + lambda permission per scheduled action definition
    backup_policy.each do |name, policy_definition|
      _process_events_rule(
        template: template,
        definitions: {
          name => {
            'Type' => 'AWS::Events::Rule',
            'Properties' => {
              'ScheduleExpression' => policy_definition['schedule_expression'],
              'Targets' => [
                {
                  'Id' => 'BackupPolicy',
                  'Input' => policy_definition['inputs'],
                  'Arn' => {
                    'Fn::Join' => [':', [
                      'arn:aws:sns',
                      { 'Ref' => 'AWS::Region' },
                      { 'Ref' => 'AWS::AccountId' },
                      engine_topic_name
                    ]]
                  }
                }
              ]
            }
          }
        }
      )
    end
  end

  # Validates account alias
  # @param account_alias [String] Backup target alias. (Eg. @ams01-origin-dev)
  def _validate_account_alias(account_alias)
    environment = Defaults.sections[:env]
    ams = Defaults.sections[:ams]
    case account_alias
    when '@origin', '@dr'
      "@#{ams}-#{account_alias.sub('@', '')}-#{environment}"
    when '@nonp'
      "@#{ams}-origin-nonp"
    when '@origin-prod', '@origin-nonp', '@origin-nonp', '@dr-prod', '@dr-nonp', '@origin-dev'
      "@#{ams}-#{account_alias.sub('@', '')}"
    when /^@ams[0-9]{2}-(origin|dr([0-9])?)-(prod|nonp|dev)$/
      account_alias
    else
      raise "Invalid value #{account_alias} specified for the account alias"
    end
  end

  # Generates set of tags to be passed to the backup engine
  # @param component_name [String] Component Name
  def _tags(component_name)
    tags = {}
    Defaults.get_tags(component_name).map { |tag| tags[tag[:key]] = tag[:value] }
    return tags
  end

  # Runs validation against the schedule expression provided by the user
  # @param schedule_expression [String] Cron or rate expression for execution.
  # @param copy_targets [Bool] Whether to validate against copy targets
  def _validate_recurrence(schedule_expression, copy_targets = false)
    # Validate cron expression based on supported syntax
    # http://docs.aws.amazon.com/AmazonCloudWatch/latest/events/ScheduledEvents.html
    # If secondary copy target is specified, restrict to time of day expression only
    # to reduce cost impact.

    cron_regex = if copy_targets
                   %r{^([0-9]+) ([0-9]+) ([0-9,\-*?\/LW]+) ([0-9A-Z,\-*?\/]+) ([1-7A-Z,\-*?\/L]+)$}
                 else
                   %r{^([0-9,\-*\/]+) ([0-9,\-*\/]+) ([0-9,\-*?\/LW]+) ([0-9A-Z,\-*?\/]+) ([1-7A-Z,\-*?\/L]+)$}
                 end

    unless schedule_expression.match(cron_regex)
      raise "Unsupported schedule expression #{schedule_expression}. "\
            'See Backup Policy documentation for supported expressions'
    end

    unless (Regexp.last_match[3] == "?") ^ (Regexp.last_match[5] == "?")
      raise "Must specify '?' for either - day-of-month or day-of-week"
    end
  end
end
