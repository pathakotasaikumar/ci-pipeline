require "consumable"
require_relative "builders/elasticache_replication_group_builder"
require_relative "builders/elasticache_parameter_group_builder"
require_relative "builders/elasticache_subnet_group_builder"
require_relative "builders/route53_record_builder"
require_relative "builders/dns_record_builder"

class AwsElastiCacheRedis < Consumable
  include ElastiCacheReplicationGroupBuilder
  include ElastiCacheParameterGroupBuilder
  include ElastiCacheSubnetGroupBuilder
  include Route53RecordBuilder
  include DnsRecordBuilder

  # @param (see Consumable#initialize)
  def initialize(component_name, definition)
    super(component_name, definition)

    @replication_group = {}
    @parameter_group = {}
    @subnet_group = {}

    # Load resources from the component definition
    (definition["Configuration"] || {}).each do |name, resource|
      type = resource["Type"]

      case type
      when "AWS::ElastiCache::ReplicationGroup"
        raise "This component does not support multiple #{type} resources" unless @replication_group.empty?

        @replication_group[name] = resource
      when "AWS::ElastiCache::ParameterGroup"
        raise "This component does not support multiple #{type} resources" unless @parameter_group.empty?

        @parameter_group["ParameterGroup"] = resource
      when "AWS::ElastiCache::SubnetGroup"
        raise "This component does not support multiple #{type} resources" unless @subnet_group.empty?

        @subnet_group["SubnetGroup"] = resource
      when "Pipeline::Features"
        @features[name] = resource
      when nil
        raise "Must specify a type for resource #{name.inspect}"
      else
        raise "Resource type #{type.inspect} is not supported by this component"
      end
    end

    raise "Must specify an AWS::ElastiCache::ReplicationGroup resource" if @replication_group.empty?

    @subnet_group = { "SubnetGroup" => {} } if @subnet_group.empty?

    @replication_group_name = @replication_group.keys.first
    @parameter_group_name = @parameter_group.keys.first
    @subnet_group_name = @subnet_group.keys.first
  end

  # @return (see Consumable#security_items)
  def security_items
    [
      {
        "Name" => "SecurityGroup",
        "Type" => "SecurityGroup",
        "Component" => @component_name,
      }
    ]
  end

  # @return (see Consumable#security_rules)
  def security_rules
    security_rules = []

    mappings = {}
    mappings["read"] = %w(
      Describe*
      List*
    )
    mappings["write"] = mappings["read"] + %w(
      CopySnapshot
      CreateSnapshot
      DeleteSnapshot
    )

    mappings["admin"] = mappings["write"] + %w(
      ModifyCacheCluster
      ModifyCacheParameterGroup
      ModifyReplicationGroup
      RebootCacheCluster
    )

    mappings.each { |key, value| mappings[key] = value.map { |s| "elasticache:#{s}" } }

    security_rules += _parse_security_rules(
      mappings: mappings,
      rules: @replication_group.values.first["Security"],
      destination_ip: "#{@component_name}.SecurityGroup",
      destination_iam: "*" # ElastiCache does not support resource-level permissions
    )

    return security_rules
  end

  # Execute deployment steps for the component
  def deploy
    # Create stack
    stack_name = Defaults.component_stack_name(@component_name)
    tags = Defaults.get_tags(@component_name)
    @pipeline_features.map { |f| tags += f.feature_tags }
    template = _build_template
    Context.component.set_variables(@component_name, "Template" => template)

    begin
      stack_outputs = {}
      stack_outputs = AwsHelper.cfn_create_stack(
        stack_name: stack_name,
        template: template,
        tags: tags
      )
    rescue => e
      stack_outputs = e.is_a?(ActionError) ? e.partial_outputs : {}
      raise "Failed to create stack - #{e}"
    ensure
      Context.component.set_variables(@component_name, stack_outputs)
    end

    # Add tags to the replication group's cache clusters
    clusters = AwsHelper.elasticache_get_replication_group_clusters(
      Context.component.variable(component_name, "#{@replication_group_name}Name")
    )
    clusters = clusters.map do |name|
      next name if name.start_with? "arn:"

      next "arn:aws:elasticache:#{Context.environment.region}:#{Context.environment.account_id}:cluster:#{name}"
    end
    AwsHelper.elasticache_set_tags(clusters, tags)

    # Create a DNS record for this component
    return unless Defaults.ad_dns_zone?

    begin
      Log.debug "Deploying AD DNS records"

      dns_name = Defaults.deployment_dns_name(
        component: @component_name,
        zone: Defaults.ad_dns_zone
      )

      endpoint = Context.component.variable(
        @component_name,
        "#{@replication_group_name}PrimaryEndPointAddress"
      )

      deploy_ad_dns_records(
        dns_name: dns_name,
        endpoint: endpoint,
        type: 'CNAME',
        ttl: '60'
      )
    rescue => error
      Log.error "Failed to deploy DNS records - #{error}"
      raise "Failed to deploy DNS records - #{error}"
    end
  end

  # Execute release for the component
  def release
    super
  end

  # Execute teardown for the component stack
  def teardown
    exception = nil

    # Delete component stack
    begin
      stack_id = Context.component.stack_id(@component_name)
      unless stack_id.nil?
        Log.info "Deleting stack with id #{stack_id.inspect}"
        AwsHelper.cfn_delete_stack(stack_id)
      end
    rescue => e
      exception ||= e
      Log.warn "Failed to delete stack #{stack_id.inspect} during teardown - #{e}"
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

  # Builds component CloudFormation template
  # @return [Hash] CloudFormation template representation
  def _build_template
    template = { "Resources" => {}, "Outputs" => {} }

    if @parameter_group.any?
      _process_elasticache_parameter_group(
        template: template,
        parameter_group: @parameter_group,
      )
    end

    _process_elasticache_subnet_group(
      template: template,
      subnet_group: @subnet_group,
    )

    security_group_ids = [Context.component.sg_id(@component_name, "SecurityGroup")]
    security_group_ids << Context.asir.destination_sg_id if ingress?

    _process_elasticache_replication_group(
      template: template,
      component_name: @component_name,
      replication_group: @replication_group,
      parameter_group_name: @parameter_group_name,
      subnet_group_name: @subnet_group_name,
      security_group_ids: security_group_ids,
    )

    unless Defaults.ad_dns_zone?
      _process_deploy_r53_dns_records(
        template: template,
        component_name: @component_name,
        zone: Defaults.r53_hosted_zone,
        resource_records: [
          JsonTools.hash_to_cfn_join(
            'Fn::GetAtt' => [@replication_group_name, 'PrimaryEndPoint.Address']
          )
        ],
        ttl: '60',
        type: 'CNAME'
      )
    end

    return template
  end
end
