require "util/json_tools"
require "util/generate_password"
require "consumable"
require "util/obj_to_text.rb"
require "services/pipeline_metadata_service"
require_relative "builders/db_subnet_group_builder"
require_relative "builders/db_option_group_builder"
require_relative "builders/db_parameter_group_builder"
require_relative "builders/db_instance_snapshot_builder"
require_relative "builders/db_cluster_snapshot_builder"
require_relative "builders/db_cluster_parameter_group_builder"
require_relative "builders/pipeline_db_instance_backup_policy_builder"
require_relative "builders/pipeline_db_cluster_backup_policy_builder"
require_relative "builders/route53_record_builder"
require_relative "builders/db_instance_builder"

# Extends Consumable class to deliver RDS component
# @attr_reader db_cluster [Hash] definition for RDS cluster
# @attr_reader db_instances [Array] list of definitions for RDS instances
class AwsRds < Consumable
  include DbInstanceSnapshotBuilder
  include DbClusterSnapshotBuilder
  include DbSubnetGroupBuilder
  include DbOptionGroupBuilder
  include DbParameterGroupBuilder
  include DbClusterParameterGroupBuilder
  include Route53RecordBuilder
  include PipelineDbInstanceBackupPolicyBuilder
  include PipelineDbClusterBackupPolicyBuilder
  include DbInstanceBuilder

  attr_reader :db_cluster
  attr_reader :db_instances

  # @param (see Consumable#initialize)
  def initialize(component_name, component)
    super(component_name, component)

    @db_instances = {}
    @db_cluster = {}
    @db_option_group = {}
    @db_parameter_group = {}
    @db_subnet_group = {}
    @db_cluster_parameters = {}
    @template = {}
    @snapshot_id = nil
    @template_parameters = {}
    @security_group_ids = nil
    @db_instance_backup_policy = {}
    @db_cluster_backup_policy = {}
    @logs_subscription_filter = {}
    @cloudwatch_logs_export = []
    @snapshot_tags = {}

    # Load resources from the component definition
    (definition["Configuration"] || {}).each do |name, resource|
      raise "Invalid resource name #{name.inspect}" unless name =~ /^[a-zA-Z][a-zA-Z0-9]*$/

      type = resource["Type"]
      case type
      when "AWS::RDS::DBInstance"
        @db_instances[name] = resource
      when "AWS::RDS::DBCluster"
        raise "This component does not support multiple #{type} resources" unless @db_cluster.empty?

        @db_cluster[name] = resource
      when "AWS::RDS::OptionGroup"
        raise "This component does not support multiple #{type} resources" unless @db_option_group.empty?

        @db_option_group["DBOptionGroup"] = resource
      when "AWS::RDS::DBParameterGroup"
        raise "This component does not support multiple #{type} resources" unless @db_parameter_group.empty?

        @db_parameter_group["DBParameterGroup"] = resource
      when "AWS::RDS::DBSubnetGroup"
        raise "This component does not support multiple #{type} resources" unless @db_subnet_group.empty?

        @db_subnet_group["DBSubnetGroup"] = resource
      when "AWS::RDS::DBClusterParameterGroup"
        raise "This component does not support multiple #{type} resources" unless @db_cluster_parameters.empty?

        @db_cluster_parameters["DBClusterParameterGroup"] = resource
      when "Pipeline::DBInstance::BackupPolicy"
        @db_instance_backup_policy[name] = resource
      when "Pipeline::DBCluster::BackupPolicy"
        @db_cluster_backup_policy[name] = resource
      when "Pipeline::Features"
        @features[name] = resource
      when "AWS::Logs::SubscriptionFilter"
        @logs_subscription_filter[name] = resource
      when nil
        raise "Must specify a type for resource #{name.inspect}"
      else
        raise "Resource type #{type.inspect} is not supported by this component"
      end
    end

    @db_subnet_group = { "DBSubnetGroup" => {} } if @db_subnet_group.empty?

    # Gather snapshot tags from definition if available.
    # Notes: for RDS with multiple replicas Backup tags must be specified on the first AWS::RDS::DBInstance resource
    if @db_cluster.any?

      @snapshot_tags = JsonTools.get(
        @db_cluster.values.first,
        "Properties.Pipeline::SourceSnapshot",
        {}
      )

    elsif @db_instances.any?

      @snapshot_tags = JsonTools.get(
        @db_instances.values.first,
        "Properties.Pipeline::SourceSnapshot",
        {}
      )
    end

    unless @snapshot_tags.is_a?(Hash)
      raise 'Pipeline::SourceSnapshot must be an Hash'
    end

    @snapshot_id = if @db_cluster.any?
                     JsonTools.get(@db_cluster.values.first, "Properties.SnapshotIdentifier", nil)
                   elsif @db_instances.any?
                     JsonTools.get(@db_instances.values.first, "Properties.DBSnapshotIdentifier", nil)
                   end

    @cloudwatch_logs_export = if @db_cluster.any?
                                JsonTools.get(@db_cluster.values.first, "Properties.EnableCloudwatchLogExports", [])
                              elsif @db_instances.any?
                                JsonTools.get(@db_instances.values.first, "Properties.EnableCloudwatchLogExports", [])
                              end
  end

  # @return (see Consumable#security_items)
  def security_items
    [
      {
        "Type" => "SecurityGroup",
        "Name" => "SecurityGroup",
        "Component" => @component_name,
        "DefaultIpIngress" => true
      }
    ]
  end

  # @return (see Consumable#security_rules)
  def security_rules
    resources = @db_cluster.empty? ? @db_instances : @db_cluster

    # Build the list of rules for each resource
    rules = []
    resources.each do |name, definition|
      (definition["Security"] || []).each do |security_rule|
        # Extract the rule source
        source = security_rule["Source"]
        raise "Must specify a security rule source" if source.nil? or source.empty?

        # Bulid the array of allow rules
        ports = Array(security_rule["Allow"])

        # Create the rule specification object
        rules << IpSecurityRule.new(
          sources: source,
          destination: "#{@component_name}.SecurityGroup",
          ports: ports
        )
      end
    end

    # Return the array of security items
    return rules
  end

  def deploy
    # Create the stack

    _validate_and_modify_rds_password
    _validate_and_modify_settings_password

    if !@snapshot_id.nil?
      @snapshot_id = if @type == 'aws/rds-aurora' || @type == 'aws/rds-aurora-postgresql'
                       _process_db_cluster_snapshot(
                         snapshot_id: @snapshot_id,
                         component_name: @component_name,
                         resource_name: @db_cluster.keys.first
                       )
                     else
                       _process_db_instance_snapshot(
                         snapshot_id: @snapshot_id,
                         component_name: @component_name,
                         resource_name: @db_instances.keys.first
                       )
                     end
    elsif @snapshot_tags.any?
      unless @snapshot_tags.keys.all? { |s| ["ase", "branch", "build", "component", "resource"].include?(s) }
        raise 'Error: Invalid arguments are passed for Pipeline::SourceSnapshot properties'
      end

      @snapshot_id = if @type == 'aws/rds-aurora' || @type == 'aws/rds-aurora-postgresql'
                       _process_target_db_cluster_snapshot(snapshot_tags: _load_snapshot_tags)
                     else
                       _process_target_db_instance_snapshot(snapshot_tags: _load_snapshot_tags)
                     end
    end

    stack_name = Defaults.component_stack_name(@component_name)
    tags = Defaults.get_tags(@component_name)
    @pipeline_features.map { |f| tags += f.feature_tags }

    @template = _build_template
    Context.component.set_variables(@component_name, { 'Template' => @template })

    _process_template_parameters
    _upload_log_artefacts(component_name: @component_name)

    begin
      stack_outputs = {}

      # Increased timeout to allow for restore from snapshot
      stack_outputs = AwsHelper.cfn_create_stack(
        stack_name: stack_name,
        template: @template,
        tags: tags,
        wait_delay: 60,
        max_attempts: 480,
        template_parameters: @template_parameters
      )
    rescue ActionError => e
      stack_outputs = e.partial_outputs
      raise "Failed to create RDS stack - #{e}"
    ensure
      Context.component.set_variables(@component_name, stack_outputs)
      # Copy all the produced log files to a local log directory
      AwsHelper.s3_download_objects(
        bucket: Context.s3.artefact_bucket_name,
        prefix: Defaults.log_upload_path(component_name: component_name, type: 'deploy'),
        local_path: "#{Defaults.logs_dir}/#{@component_name}/deploy",
        validate: false
      )
    end

    # Enable CopyTagsToSnapshot property on RDS Clusters only, CloudFormations supports AWS::RDS::DBInstance CopyTagsToSnapshot
    # To be refactored when Cloudformation updates the AWS::RDS::DBCluster resource
    if @db_cluster.any?
      name = @db_cluster.keys.first
      db_cluster_arn = Context.component.variable(@component_name, "#{name}Arn")

      # Race condition when Cluster is still updating but Cloudformation stack signals complete prematurely
      AwsHelper.rds_wait_for_status_available(
        component_name: @component_name,
        db_cluster_identifier: db_cluster_arn
      )

      AwsHelper.rds_enable_copy_tags_to_snapshot(
        component_name: @component_name,
        db_cluster_identifier: db_cluster_arn,
        copy_tags_to_snapshot: true
      )
      Log.output("Sucessful enablement of CopyTagsToSnapshot for #{@component_name}")
    end

    # Resetting the database password when its restored from snapshot
    _reset_rds_database_password unless @snapshot_id.nil?

    # Enable Cloudwatch logs for the RDS Instance if cloudwatch_logs_export is set
    if !@cloudwatch_logs_export.empty?

      if @db_cluster.any?

        # Enable the exporting of the logs to KMS key
        AwsHelper.rds_enable_cloudwatch_logs_export(
          db_cluster_identifier: Context.component.variable(@component_name, "#{@db_cluster.keys.first}Arn"),
          component_name: @component_name,
          enable_log_types: @cloudwatch_logs_export
        )

      elsif @db_instances.any?

        AwsHelper.rds_enable_cloudwatch_logs_export(
          db_instance_identifier: Context.component.variable(@component_name, "#{@db_instances.keys.first}Arn"),
          component_name: @component_name,
          enable_log_types: @cloudwatch_logs_export
        )

      end

    end

    # Create deployment DNS names
    begin
      if Defaults.ad_dns_zone?
        Log.debug 'Deploying AD DNS records'
        deploy_rds_ad_dns_records
      end
    rescue => error
      Log.error "Failed to deploy DNS records - #{error}"
      raise "Failed to deploy DNS records - #{error}"
    end
  end

  # Execute release for the component
  def release
    super
  end

  def create_ad_release_dns_records(component_name:)
    if @db_cluster.any?
      engine_mode = JsonTools.get(@db_cluster.values.first, "Properties.EngineMode", nil)
    elsif @db_instances.any?
      engine_mode = nil
    end
    # Update the release DNS endpoint for cluster
    unless !engine_mode.nil?
      @db_cluster.merge(@db_instances).keys.each do |name|
        dns_name = Defaults.release_dns_name(
          component: component_name,
          resource: name,
          zone: Defaults.ad_dns_zone
        )

        endpoint = Context.component.variable(component_name, "#{name}DeployDnsName")
        Util::Nsupdate.create_dns_record(dns_name, endpoint, "CNAME", 60)
        # Print AD Release records only if Route53 zone is not specified
        Log.output("#{component_name} #{name} Endpoint DNS: #{dns_name}") if Defaults.ad_dns_zone?
      end

      @db_cluster.keys.each do |name|
        dns_name = Defaults.release_dns_name(
          component: component_name,
          resource: "#{name}-ro",
          zone: Defaults.ad_dns_zone
        )
        # backwards compatibility with builds prior to introduction of reader endpoint
        next if dns_name.nil?

        endpoint = Context.component.variable(component_name, "#{name}ReaderDeployDnsName")
        Util::Nsupdate.create_dns_record(dns_name, endpoint, "CNAME", 60)

        # Print AD Release records only if Route53 zone is not specified
        Log.output("#{component_name} #{name} Reader Endpoint DNS: #{dns_name}") if Defaults.ad_dns_zone?
      end
    else
      @db_cluster.keys.each do |name|
        dns_name = Defaults.release_dns_name(
          component: component_name,
          resource: name,
          zone: Defaults.ad_dns_zone
        )

        endpoint = Context.component.variable(component_name, "#{name}DeployDnsName")
        Util::Nsupdate.create_dns_record(dns_name, endpoint, "CNAME", 60)
        # Print AD Release records only if Route53 zone is not specified
        Log.output("#{component_name} #{name} Endpoint DNS: #{dns_name}") if Defaults.ad_dns_zone?
      end
    end
  end

  def teardown
    exception = nil

    # Take last snapshot in production environments
    _take_last_backup if Defaults.sections[:env] == "prod" || Context.environment.qa?

    begin
      stack_id = Context.component.stack_id(@component_name)
      AwsHelper.cfn_delete_stack(stack_id) unless stack_id.nil?
    rescue => e
      exception ||= e
      Log.warn "Failed to delete component #{@component_name} stack #{stack_id.inspect} during teardown - #{e}"
    end

    # Delete temporary snapshots
    begin
      temp_snapshots = Context.component.variable(@component_name, 'TempSnapshots', []).uniq.compact
      unless temp_snapshots.empty?
        if @type == 'aws/rds-aurora' || @type == 'aws/rds-aurora-postgresql'
          AwsHelper.rds_delete_db_cluster_snapshots(temp_snapshots)
        else
          AwsHelper.rds_delete_db_instance_snapshots(temp_snapshots)
        end
        Log.info "Deleted temporary snapshots #{temp_snapshots}"
      end
    rescue => e
      Log.warn "Failed to delete temporary snapshots #{temp_snapshots} - #{e}"
    end

    # Clean up deployment DNS records
    begin
      _clean_rds_ad_deployment_dns_record
      _clean_rds_ad_release_dns_record if Context.persist.released_build? || Context.persist.released_build_number.nil?
    rescue => e
      exception ||= e
      Log.warn "Failed to remove AD DNS records during teardown - #{e}"
    end

    raise exception unless exception.nil?
  end

  # @return (see Consumable#dns_records)
  def name_records
    records = {}

    # Generate individual DNS records per RDS instance
    @db_cluster.merge(@db_instances).keys.each do |name|
      records["#{name}DeployDnsName"] = Defaults.deployment_dns_name(
        component: component_name,
        resource: name,
        zone: Defaults.dns_zone
      )
      records["#{name}ReleaseDnsName"] = Defaults.release_dns_name(
        component: component_name,
        resource: name,
        zone: Defaults.dns_zone
      )
    end

    @db_cluster.keys.each do |name|
      records["#{name}ReaderDeployDnsName"] = Defaults.deployment_dns_name(
        component: component_name,
        resource: "#{name}-ro",
        zone: Defaults.dns_zone
      )
      records["#{name}ReaderReleaseDnsName"] = Defaults.release_dns_name(
        component: component_name,
        resource: "#{name}-ro",
        zone: Defaults.dns_zone
      )
    end

    return records
  end

  def process_release_r53_dns_record(
    template:,
    zone:,
    component_name:
  )
    @db_cluster.merge(@db_instances).keys.each do |name|
      dns_name = Defaults.release_dns_name(
        component: component_name,
        resource: name,
        zone: Defaults.dns_zone
      )

      _process_route53_records(
        template: template,
        record_sets: {
          "#{component_name}#{name}ReleaseDns".gsub(/[^a-zA-Z0-9]/, '') => {
            "Properties" => {
              "Name" => dns_name,
              "Type" => "CNAME",
              "TTL" => "60",
              "HostedZoneName" => zone,
              "ResourceRecords" => [
                Context.component.variable(component_name, "#{name}DeployDnsName")
              ]
            }
          }
        }
      )

      Log.output "#{name} DNS: #{dns_name}"
    end

    @db_cluster.keys.each do |name|
      dns_name = Defaults.release_dns_name(
        component: component_name,
        resource: name,
        zone: Defaults.dns_zone
      )

      dns_name_ro = Defaults.release_dns_name(
        component: component_name,
        resource: "#{name}-ro",
        zone: Defaults.dns_zone
      )

      _process_route53_records(
        template: template,
        record_sets: {
          "#{component_name}#{name}ReleaseDns".gsub(/[^a-zA-Z0-9]/, '') => {
            "Properties" => {
              "Name" => dns_name,
              "Type" => "CNAME",
              "TTL" => "60",
              "HostedZoneName" => zone,
              "ResourceRecords" => [
                Context.component.variable(component_name, "#{name}DeployDnsName")
              ]
            }
          },
          "#{component_name}#{name}ReadOnlyReleaseDns".gsub(/[^a-zA-Z0-9]/, '') => {
            "Properties" => {
              "Name" => dns_name_ro,
              "Type" => "CNAME",
              "TTL" => "60",
              "HostedZoneName" => zone,
              "ResourceRecords" => [
                Context.component.variable(component_name, "#{name}ReaderDeployDnsName")
              ]
            }
          }
        }
      )
      Log.output "#{name} Master DNS: #{dns_name}"
      Log.output "#{name} ReadOnlyReader DNS: #{dns_name_ro}"
    end
  end

  protected

  # uploads logs to S3 bucket
  # later, these files are made available in bamboo artifacvts tab
  # we need to expose db creds that way
  def _upload_log_artefacts(component_name:)
    Log.info 'Creating component variables file for use by the db'

    objects = {}
    context = Context.component.variables || {}

    skip_keys = ['Template', '_private_']

    context = context.inject({}) do |memo, (key, value)|
      next memo if skip_keys.any? { |skip_key| key.include? skip_key }

      # Encrypt the value if it is a password
      if value.is_a? String and key.downcase.include? "password"
        value = AwsHelper.kms_encrypt_data(Context.kms.secrets_key_arn, value)
      end
      memo[key] = value
      memo
    end

    objects['context'] = ObjToText.generate_flat_config(
      variables: context.sort.to_h,
      quote_strings: true,
      line_prefix: 'export '
    )

    artefact_bucket = Context.s3.artefact_bucket_name
    logs_artefact_path = Defaults.log_upload_path(component_name: component_name, type: 'deploy')

    # Upload the objects
    objects.each do |name, contents|
      AwsHelper.s3_put_object(artefact_bucket, "#{logs_artefact_path}/#{name}", contents)
    end
  end

  # Fills @template_parameters with template specific parameters taken from Context.component variables
  def _process_template_parameters
    # promoting every 'MasterUsername/MasterUserPassword' property to be a template parameter
    # such props can come either from @db_instances or from @db_cluster (for Aurora) or from something else
    # builders put them into template['Parameters'] so we can lookup them up safely

    return unless @template.key? 'Parameters'

    template_params = @template['Parameters']

    template_params.keys.each do |name|
      next unless name.is_a? String
      next unless name.downcase.include?('masterusername') || name.downcase.include?('password')

      param_value = Context.component.variable(@component_name, name, '')

      if param_value == :undef || param_value.nil? || param_value.empty?
        raise "Context variable [#{name}] is undefined, nil or empty"
      end

      @template_parameters[name] = param_value
    end
  end

  # @return template [Hash] Reference to template
  def _build_template
    # logic implemented in subclasses
    @template = { "Resources" => {}, "Outputs" => {} }

    @security_group_ids = [Context.component.sg_id(@component_name, "SecurityGroup")]
    @security_group_ids << Context.asir.destination_sg_id if ingress?

    if @db_cluster.any?
      stack_deletion_policy = JsonTools.get(@db_cluster.values.first, "DeletionPolicy", nil)
    elsif @db_instances.any?
      stack_deletion_policy = JsonTools.get(@db_instances.values.first, "DeletionPolicy", nil)
    else
      stack_deletion_policy = nil
    end

    if stack_deletion_policy == "Snapshot"
      db_optiongroup_deletionpolicy = "Retain"
    else
      db_optiongroup_deletionpolicy = "Delete"
    end

    # Generate DbSubnetGroup resource
    _process_db_subnet_group(
      template: @template,
      db_subnet_group: @db_subnet_group,
    )

    _process_db_option_group(
      template: @template,
      component_name: @component_name,
      db_option_groups: @db_option_group,
      db_option_groups_deletionpolicy: db_optiongroup_deletionpolicy
    )

    _process_db_parameter_groups(
      template: @template,
      db_parameter_groups: @db_parameter_group
    )

    _process_db_cluster_parameter_group(
      template: @template,
      db_cluster_parameter_group: @db_cluster_parameters
    )

    if @db_instance_backup_policy.any?

      policy_definitions = _parse_db_instance_backup_policy(
        resource_id: { 'Ref' => @db_instances.keys.first },
        definitions: @db_instance_backup_policy,
        component_name: @component_name
      )

      _process_backup_policy(
        template: @template,
        backup_policy: policy_definitions
      )
    end

    if @db_cluster_backup_policy.any?

      policy_definitions = _parse_db_cluster_backup_policy(
        resource_id: { 'Ref' => @db_cluster.keys.first },
        definitions: @db_cluster_backup_policy,
        component_name: @component_name
      )

      _process_backup_policy(
        template: @template,
        backup_policy: policy_definitions
      )
    end

    # Create deployment DNS records
    unless Defaults.ad_dns_zone?
      _process_db_instance_deploy_r53_dns_records(
        template: @template,
        zone: Defaults.dns_zone
      )
    end

    return @template
  end

  def deploy_rds_ad_dns_records
    if @db_cluster.any?
      engine_mode = JsonTools.get(@db_cluster.values.first, "Properties.EngineMode", nil)
    elsif @db_instances.any?
      engine_mode = nil
    end

    unless !engine_mode.nil?
      # Create deployment DNS names
      @db_cluster.merge(@db_instances).keys.each do |name|
        dns_name = Defaults.deployment_dns_name(
          component: component_name,
          resource: name,
          zone: Defaults.ad_dns_zone
        )
        endpoint = Context.component.variable(@component_name, "#{name}EndpointAddress")
        Util::Nsupdate.create_dns_record(dns_name, endpoint, "CNAME", 60)
        Log.output("#{@component_name} #{name} DNS: #{dns_name}")
      end

      @db_cluster.keys.each do |name|
        dns_name = Defaults.deployment_dns_name(
          component: component_name,
          resource: "#{name}-ro",
          zone: Defaults.ad_dns_zone
        )
        endpoint = Context.component.variable(@component_name, "#{name}ReaderEndpointAddress")
        Util::Nsupdate.create_dns_record(dns_name, endpoint, "CNAME", 60)
        Log.output("#{@component_name} #{name} Reader DNS: #{dns_name}")
      end
    else
      @db_cluster.keys.each do |name|
        dns_name = Defaults.deployment_dns_name(
          component: component_name,
          resource: name,
          zone: Defaults.ad_dns_zone
        )
        endpoint = Context.component.variable(@component_name, "#{name}EndpointAddress")
        Util::Nsupdate.create_dns_record(dns_name, endpoint, "CNAME", 60)
        Log.output("#{@component_name} #{name} DNS: #{dns_name}")
      end
    end
  end

  def _process_db_instance_deploy_r53_dns_records(template:, zone:)
    # Create deployment DNS records
    @db_instances.keys.each do |name|
      dns_name = Defaults.deployment_dns_name(
        component: component_name,
        resource: name,
        zone: zone
      )
      _process_route53_records(
        template: template,
        record_sets: {
          "#{name}DeployDns" => {
            "Properties" => {
              "Name" => dns_name,
              "Type" => "CNAME",
              "TTL" => "60",
              "ResourceRecords" => [
                { "Fn::GetAtt" => [name, "Endpoint.Address"] }
              ]
            }
          }
        }
      )
      Log.output("#{@component_name} DNS: #{dns_name}")
    end
  end

  def _clean_rds_ad_deployment_dns_record
    # Skip clean up of records unless AD dns zone is used or global teardown
    return unless Defaults.ad_dns_zone? || Context.environment.variable('custom_buildNumber', nil)

    # Clean up deployment DNS records
    @db_cluster.merge(@db_instances).keys.each do |name|
      begin
        dns_name = Defaults.deployment_dns_name(
          component: component_name,
          resource: name,
          zone: Defaults.ad_dns_zone
        )
        Util::Nsupdate.delete_dns_record(dns_name) unless dns_name.nil?
      rescue => e
        Log.error "Failed to delete DNS record #{dns_name} during teardown - #{e}"
        raise "Failed to delete DNS record #{dns_name} during teardown - #{e}"
      end
    end

    @db_cluster.keys.each do |name|
      begin
        reader_dns_name = Defaults.deployment_dns_name(
          component: component_name,
          resource: "#{name}-ro",
          zone: Defaults.ad_dns_zone
        )
        Util::Nsupdate.delete_dns_record(reader_dns_name) unless reader_dns_name.nil?
      rescue => e
        Log.error "Failed to delete DNS record #{reader_dns_name} during teardown - #{e}"
        raise "Failed to delete DNS record #{reader_dns_name} during teardown - #{e}"
      end
    end
  end

  def _clean_rds_ad_release_dns_record
    # Clean up release DNS records if required
    @db_cluster.merge(@db_instances).keys.each do |name|
      begin
        dns_name = Defaults.release_dns_name(
          component: component_name,
          resource: name,
          zone: Defaults.ad_dns_zone
        )
        Util::Nsupdate.delete_dns_record(dns_name) unless dns_name.nil?
      rescue => e
        Log.warn "Failed to delete DNS record #{dns_name} during teardown - #{e}"
      end
    end

    @db_cluster.keys.each do |name|
      begin
        reader_dns_name = Defaults.release_dns_name(
          component: component_name,
          resource: "#{name}-ro",
          zone: Defaults.ad_dns_zone
        )
        Util::Nsupdate.delete_dns_record(reader_dns_name) unless reader_dns_name.nil?
      rescue => e
        Log.warn "Failed to delete DNS record #{reader_dns_name} during teardown - #{e}"
      end
    end
  end

  # Construct the RDS snapshot tags
  # @return (Hash)
  def _load_snapshot_tags
    sections = Defaults.sections
    resource_name = @type == 'aws/rds-aurora' || @type == 'aws/rds-aurora-postgresql' ? @db_cluster.keys.first : @db_instances.keys.first
    default_tags = {
      ase: "#{sections[:ase]}",
      branch: "#{sections[:branch]}",
      component: @component_name,
      resource: "#{resource_name}"
    }

    @snapshot_tags.keys.each { |key| @snapshot_tags[key.to_sym] = @snapshot_tags.delete(key) }

    default_tags = default_tags.merge(@snapshot_tags)
    if default_tags[:build].nil?
      default_tags[:build] = PipelineMetadataService.load_metadata(**default_tags)
    end
    default_tags
  end

  private

  def _validate_and_modify_rds_password
    db_master_password = if @db_cluster.any?
                           JsonTools.get(@db_cluster.values.first, "Properties.MasterUserPassword", nil)
                         elsif @db_instances.any?
                           JsonTools.get(@db_instances.values.first, "Properties.MasterUserPassword", nil)
                         end

    unless db_master_password.nil?
      unless db_master_password =~ /^@app.([0-9a-zA-Z_\/]+)$/
        raise ArgumentError, "DB Password can't be set as plaintext value."\
                "Please use the QCP Secret Manager to encrypt the password and reference it in your YAML."
      else
        if @db_cluster.any?
          _process_db_password(definition: @db_cluster.values.first)
        else
          _process_db_password(definition: @db_instances.values.first)
        end
      end
    end
  end

  def _validate_and_modify_settings_password
    # find all the passwords in the option group nest
    @db_option_group.each do |name, definition|
      option_configs = JsonTools.get(definition, "Properties.OptionConfigurations")
      option_configs.each do |config|
        if config.key? "OptionSettings"
          config.fetch("OptionSettings").each do |setting|
            if setting["Name"].downcase.include? "password"
              unless setting["Value"] =~ /^@app.([0-9a-zA-Z_\/]+)$/
                raise ArgumentError, "Password can't be set as plaintext value."\
                        "Please use the QCP Secret Manager to encrypt the password and reference it in your YAML."
              else
                _process_settings_password(settings_definition: setting)
              end
            end
          end
        end
      end
    end
  end

  def _reset_rds_database_password
    resetDatabasePassword = if @db_cluster.any?
                              JsonTools.get(@db_cluster.values.first, "Properties.Pipeline::ResetMasterUserPassword", false)
                            elsif @db_instances.any?
                              JsonTools.get(@db_instances.values.first, "Properties.Pipeline::ResetMasterUserPassword", false)
                            end

    if resetDatabasePassword

      databasePassword = if @db_cluster.any?
                           JsonTools.get(@db_cluster.values.first, "Properties.MasterUserPassword", GeneratePassword.generate)
                         elsif @db_instances.any?
                           JsonTools.get(@db_instances.values.first, "Properties.MasterUserPassword", GeneratePassword.generate)
                         end

      if @db_cluster.any?
        name = @db_cluster.keys.first
        AwsHelper.rds_reset_password(
          db_cluster_identifier: Context.component.variable(@component_name, "#{name}Arn"),
          component_name: @component_name,
          password: databasePassword
        )
      elsif @db_instances.any?
        name = @db_instances.keys.first
        AwsHelper.rds_reset_password(
          db_instance_identifier: Context.component.variable(@component_name, "#{name}Arn"),
          component_name: @component_name,
          password: databasePassword
        )
      end
      Context.component.set_variables(
        @component_name,
        "#{name}MasterUserPassword" => databasePassword
      )
    end
  rescue ActionError => e
    raise "Failed to reset the RDS Database password - #{e}"
  end

  def _take_last_backup
    begin
      last_backup_snapshot = nil

      if @type == 'aws/rds-aurora' || @type == 'aws/rds-aurora-postgresql'
        last_backup_snapshot = _process_db_cluster_snapshot(
          snapshot_id: 'take-snapshot',
          component_name: @component_name,
          resource_name: @db_cluster.keys.first
        )
      else
        last_backup_snapshot = _process_db_instance_snapshot(
          snapshot_id: 'take-snapshot',
          component_name: @component_name,
          resource_name: @db_instances.keys.first
        )
      end

      Log.output "Successfully created last backup snapshot for component #{@component_name} as #{last_backup_snapshot}"
    rescue => e
      if Context.environment.variable('force_teardown_of_released_build', nil) == 'true'
        Log.info "Skipping failure of create last backup snapshot for component #{@component_name} during teardown - #{e}"
      else
        Log.error "Failed to create last backup snapshot for component #{@component_name} during teardown - #{e}"
        raise
      end
    end
  end
end
