require 'util/json_tools'
require 'util/generate_password'
require 'consumable'
require 'consumables/aws/aws_rds'

require_relative 'builders/db_instance_oracle_builder'
require_relative 'builders/logs_loggroup_builder'
require_relative 'builders/logs_subscriptionfilter_builder'

class AwsRdsOracle < AwsRds
  include DbInstanceOracleBuilder
  include LogsLoggroupBuilder
  include LogsSubscriptionFilterBuilder

  def initialize(component_name, component)
    super
    raise "Resource type \"AWS::RDS::DBCluster\" is not supported by this component" unless @db_cluster.empty?
  end

  def security_items
    super
  end

  def security_rules
    super
  end

  def deploy
    super
  end

  def release
    super
  end

  def teardown
    super
  end

  def _build_template
    super

    # Create the Log Group and Subscription Filter resources if log exports are
    # defined.
    dependsOn = []
    @cloudwatch_logs_export.each do |logtype|
      _process_logs_loggroup(
        template: @template,
        definitions: {
          "#{@db_instances.keys.first}#{logtype}LogGroup" => {
            "Properties" => {
              "LogGroupName" => "/aws/rds/instance/#{Defaults.resource_name(@component_name, @db_instances.keys.first)}/#{logtype}",
              "RetentionInDays" => 1
            },
            "DependsOn" => "#{@db_instances.keys.first}"
          }
        }
      )
      dependsOn.push("#{@db_instances.keys.first}#{logtype}LogGroup")

      next unless @logs_subscription_filter.any?

      filter_name, definition = @logs_subscription_filter.first

      _process_logs_subscription_filter(
        template: @template,
        log_group: { 'Ref' => "#{@db_instances.keys.first}#{logtype}LogGroup" },
        definitions: { "#{filter_name}#{logtype}" => definition }
      )
    end

    # Generate DbInstance resources
    _process_db_instances(
      template: @template,
      db_instance_definitions: @db_instances,
      security_group_ids: @security_group_ids,
      db_parameter_group: @db_parameter_group,
      db_option_group: @db_option_group,
      snapshot_identifier: @snapshot_id,
      component_name: @component_name,
      dependsOn: dependsOn
    )

    return @template
  end
end
