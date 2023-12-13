require "util/json_tools"
require "util/generate_password"
require "consumable"
require "consumables/aws/aws_rds"

require_relative "builders/db_cluster_aurora_builder"
require_relative "builders/db_instance_aurora_builder"
require_relative 'builders/logs_loggroup_builder'
require_relative 'builders/logs_subscriptionfilter_builder'

class AwsRdsAurora < AwsRds
  include DbInstanceAuroraBuilder
  include DbClusterAuroraBuilder
  include LogsLoggroupBuilder
  include LogsSubscriptionFilterBuilder

  def initialize(component_name, component, engine_name = "aurora")
    super(component_name, component)
    @engine_name = engine_name
    raise "Cannot specify multiple AWS::RDS::DBClusterParameterGroup resources in the same definition" if @db_cluster_parameters.length > 1
    raise "Must have at least one resource of type AWS::RDS::DBCluster" if @db_cluster.empty?
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

    instance_classes = []
    storage_encrypted = true

    @db_instances.values.each do |definition|
      instance_classes << JsonTools.get(definition, "Properties.DBInstanceClass", nil)
    end

    # Create the Log Group and Subscription Filter resources if log exports are
    # defined.
    dependsOn = []
    @cloudwatch_logs_export.each do |logtype|
      _process_logs_loggroup(
        template: @template,
        definitions: {
          "#{@db_cluster.keys.first}#{logtype}LogGroup" => {
            "Properties" => {
              "LogGroupName" => "/aws/rds/cluster/#{Defaults.resource_name(@component_name, @db_cluster.keys.first)}/#{logtype}",
              "RetentionInDays" => 1
            }
          }
        }
      )
      dependsOn.push("#{@db_cluster.keys.first}#{logtype}LogGroup")

      next unless @logs_subscription_filter.any?

      filter_name, definition = @logs_subscription_filter.first

      _process_logs_subscription_filter(
        template: @template,
        log_group: { 'Ref' => "#{@db_cluster.keys.first}#{logtype}LogGroup" },
        definitions: { "#{filter_name}#{logtype}" => definition }
      )
    end

    engine_port = _get_port_from_engine_name(@engine_name)

    # Generate DbCluster resource
    _process_db_cluster(
      template: @template,
      db_cluster_definition: @db_cluster,
      db_cluster_parameters: @db_cluster_parameters,
      security_group_ids: @security_group_ids,
      snapshot_identifier: @snapshot_id,
      component_name: @component_name,
      storage_encrypted: storage_encrypted,
      engine_name: @engine_name,
      engine_port: engine_port,
      dependsOn: dependsOn
    )

    engine_mode = JsonTools.get(@db_cluster.values.first, "Properties.EngineMode", "provisioned")
    # Generate DbInstance resources
    if engine_mode != 'serverless'
      _process_db_instances(
        template: @template,
        db_instance_definitions: @db_instances,
        db_parameter_group: @db_parameter_group,
        db_cluster_name: @db_cluster.keys.first,
        engine_name: @engine_name,
        component_name: @component_name,
        dependsOn: dependsOn
      )
    end
    unless Defaults.ad_dns_zone?
      _process_db_cluster_deploy_r53_dns_records(
        template: @template,
        zone: Defaults.dns_zone,
        db_cluster_name: @db_cluster.keys.first
      )
    end

    return @template
  end

  def _process_db_cluster_deploy_r53_dns_records(
    template:,
    zone:,
    db_cluster_name:
  )
    dns_name = Defaults.deployment_dns_name(
      component: @component_name,
      resource: db_cluster_name,
      zone: zone
    )

    dns_name_ro = Defaults.deployment_dns_name(
      component: @component_name,
      resource: "#{db_cluster_name}-ro",
      zone: zone
    )

    # Create cluster DNS records
    _process_route53_records(
      template: template,
      record_sets: {
        # Master DNS Record
        "ClusterDeployDns" => {
          "Properties" => {
            "Name" => dns_name,
            "Type" => "CNAME",
            "TTL" => "60",
            "ResourceRecords" => [{
              "Fn::GetAtt" => [db_cluster_name, "Endpoint.Address"]
            }]
          }
        },
        # Master ReadOnly Record
        "ClusterReadOnlyDeployDns" => {
          "Properties" => {
            "Name" => dns_name_ro,
            "Type" => "CNAME",
            "TTL" => "60",
            "HostedZoneName" => zone,
            "ResourceRecords" => [
              _aurora_readonly_dns(db_cluster_name)
            ]
          }
        }
      }
    )
    Log.output("#{@component_name} DNS: #{dns_name}")
    if engine_mode != 'serverless'
      Log.output("#{@component_name} DNS: #{dns_name_ro}")
    end
  end

  private

  def _get_port_from_engine_name(engine_name)
    case engine_name
    when "aurora"
      "3306"
    when "aurora-mysql"
      "3306"
    when "aurora-postgresql"
      "5432"
    else
      raise "Unknown engine name: #{engine_name}"
    end
  end
end
