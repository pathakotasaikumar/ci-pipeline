require "consumable"
require "util/json_tools"
require_relative "builders/route53_record_builder"
require_relative "builders/volume_snapshot_builder"
require_relative "builders/pipeline_volume_backup_policy_builder"
require_relative "builders/volume_builder"
require_relative 'builders/dns_record_builder'
require "services/pipeline_metadata_service"

# Extends Consumable class to delivery EC2 Volume component
# @attr_reader volume [Hash] definition for AWS::EC2::Volume resource
class AwsVolume < Consumable
  include VolumeBuilder
  include VolumeSnapshotBuilder
  include PipelineVolumeBackupPolicyBuilder
  include Route53RecordBuilder
  include DnsRecordBuilder

  attr_reader :volume

  # @param (see Consumable#initialize)
  def initialize(component_name, definition)
    super(component_name, definition)

    @volume = {}
    @snapshot_id = nil
    @backup_policy = {}

    # Load resources from the component definition
    (definition["Configuration"] || {}).each do |name, resource|
      raise "Invalid resource name #{name.inspect}" unless name =~ /^[a-zA-Z][a-zA-Z0-9]*$/

      type = resource["Type"]
      case type
      when "AWS::EC2::Volume"
        raise "This component does not support multiple #{type} resources" unless @volume.empty?

        @volume[name] = resource
      when 'Pipeline::Volume::BackupPolicy'
        @backup_policy[name] = resource
      when "Pipeline::Features"
        @features[name] = resource
      when nil
        raise "Must specify a type for resource #{name.inspect}"
      else
        raise "Resource type #{type.inspect} is not supported by this component"
      end
    end

    raise "Must specify a AWS::EC2::Volume resource" if @volume.empty?

    @volume_name = @volume.keys.first

    # Gather snapshot_id from definition if available.
    @snapshot_id = JsonTools.get(@volume.values.first, "Properties.SnapshotId", nil)
    @snapshot_tags = JsonTools.get(
      @volume.values.first,
      "Properties.Pipeline::SourceSnapshot",
      {}
    )
    unless @snapshot_tags.is_a?(Hash)
      raise 'Pipeline::SourceSnapshot must be an Hash'
    end
  end

  # @return (see Consumable#security_items)
  def security_items
    []
  end

  # @return (see Consumable#security_rules)
  def security_rules
    name, definition = @volume.first
    security_rules = []

    mappings = {}
    mappings["write"] = %w(
      ec2:AttachVolume
      ec2:DetachVolume
      ec2:EnableVolumeIO
    )

    security_rules += _parse_security_rules(
      type: :iam,
      mappings: mappings,
      rules: definition["Security"],
      destination: Context.component.variable(@component_name, "#{@volume_name}Arn", nil)
    )

    return security_rules
  end

  def deploy
    # Create the stack
    stack_name = Defaults.component_stack_name(@component_name)
    tags = Defaults.get_tags(@component_name)
    @pipeline_features.map { |f| tags += f.feature_tags }
    # Calling this method to determine the correct Snapshot ID
    if !@snapshot_id.nil?
      @snapshot_id = _process_volume_snapshot(
        snapshot_id: @snapshot_id,
        component_name: @component_name,
        resource_name: @volume_name
      )
    elsif @snapshot_tags.any?
      unless @snapshot_tags.keys.all? { |s| ["ase", "branch", "build", "component"].include?(s) }
        raise 'Error: Invalid arguments are passed for Pipeline::SourceSnapshot properties'
      end

      @snapshot_id = _process_target_volume_snapshot(snapshot_tags: _load_volume_snaps_tags)
    end
    template = _build_template
    Context.component.set_variables(@component_name, { "Template" => template })

    begin
      stack_outputs = {}
      stack_outputs = AwsHelper.cfn_create_stack(
        stack_name: stack_name,
        template: template,
        wait_delay: 60,
        max_attempts: 480,
        tags: tags
      )
    rescue ActionError => e
      stack_outputs = e.partial_outputs
      raise "Failed to create Volume stack - #{e}"
    ensure
      Context.component.set_variables(@component_name, stack_outputs)
    end
    return unless Defaults.ad_dns_zone?

    begin
      Log.debug "Deploying AD DNS records"

      dns_name = Defaults.deployment_dns_name(
        component: component_name,
        zone: Defaults.ad_dns_zone
      )

      endpoint = Context.component.variable(
        component_name,
        "#{@volume_name}Arn"
      )

      deploy_ad_dns_records(
        dns_name: dns_name,
        endpoint: endpoint,
        type: 'TXT',
        ttl: '60'
      )
    rescue => error
      Log.error "Failed to deploy DNS records - #{error}"
      raise "Failed to deploy DNS records - #{error}"
    end
  end

  def release
    super
  end

  def teardown
    exception = nil

    # Wait for volume to become available (detached)
    begin
      volume_id = Context.component.variable(@component_name, "#{@volume_name}Id", nil)
      AwsHelper.ec2_wait_until_volume_available(volume_id: volume_id) unless volume_id.nil?
    rescue => e
      Log.info "#{e}"
    end

    # Delete component stack
    begin
      stack_id = Context.component.stack_id(@component_name)
      AwsHelper.cfn_delete_stack(stack_id) unless stack_id.nil?
    rescue => e
      exception ||= e
      Log.warn "Failed to delete component #{component_name} stack #{stack_id.inspect} during teardown - #{e}"
    end

    # Delete temporary snapshots
    begin
      temp_snapshots = Context.component.variable(@component_name, 'TempSnapshots', []).uniq.compact
      unless temp_snapshots.nil? || temp_snapshots.empty?
        AwsHelper.ec2_delete_snapshots(temp_snapshots)
        Log.info "Deleted temporary snapshots #{temp_snapshots}"
      end
    rescue => e
      Log.warn "Failed to delete temporary snapshots #{temp_snapshots} - #{e}"
    end

    begin
      _clean_ad_deployment_dns_record(@component_name)
      _clean_ad_release_dns_record(@component_name)
    rescue => e
      exception ||= e
      Log.warn "Failed to remove AD DNS records during teardown - #{e}"
    end

    raise exception unless exception.nil?
  end

  private

  def _build_template
    template = { "Resources" => {}, "Outputs" => {} }

    # Generate DbSubnetGroup resource
    _process_volume(
      template: template,
      volume_definition: @volume,
      snapshot_id: @snapshot_id
    )

    if @backup_policy.any?

      policy_definitions = _parse_volume_backup_policy(
        resource_id: { 'Ref' => @volume_name },
        definitions: @backup_policy,
        component_name: @component_name
      )

      _process_backup_policy(
        template: template,
        backup_policy: policy_definitions
      )

    end

    unless Defaults.ad_dns_zone?
      _process_deploy_r53_dns_records(
        template: template,
        component_name: @component_name,
        zone: Defaults.r53_hosted_zone,
        resource_records: [JsonTools.hash_to_cfn_join("Ref" => @volume_name)],
        ttl: '60',
        type: 'TXT'
      )
    end

    return template
  end

  # Construct the EBS volume snapshot tags
  # @return (Hash)
  def _load_volume_snaps_tags
    sections = Defaults.sections
    default_tags = {
      ase: sections[:ase],
      branch: "#{sections[:branch]}",
      component: @component_name,
      resource: @volume_name
    }
    @snapshot_tags.keys.each { |key| @snapshot_tags[key.to_sym] = @snapshot_tags.delete(key) }

    default_tags = default_tags.merge(@snapshot_tags)
    if default_tags[:build].nil?
      default_tags[:build] = PipelineMetadataService.load_metadata(**default_tags)
    end
    default_tags
  end
end
