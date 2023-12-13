require "util/json_tools"
require "util/obj_to_text"
require "util/user_data"
require "consumable"

require_relative "builders/instance_profile_builder"
require_relative "builders/emr_cluster_builder"
require_relative "builders/emr_step_builder"
require_relative "builders/emr_instance_group_config_builder"
require_relative "builders/emr_scheduled_action_builder"
require_relative "builders/instance_profile_builder"
require_relative "builders/route53_record_builder"
require_relative "builders/dns_record_builder"

class AwsEmrCluster < Consumable
  include InstanceProfileBuilder
  include EmrClusterBuilder
  include EmrStepBuilder
  include EmrInstanceGroupConfigBuilder
  include EMRScheduledActionBuilder
  include Route53RecordBuilder
  include DnsRecordBuilder

  def initialize(component_name, component)
    super(component_name, component)

    @cluster = {}
    @instance_group_configs = {}
    @steps = {}
    @scheduled_actions = {}

    # Load resources from the component definition
    (definition["Configuration"] || {}).each do |name, resource|
      type = resource["Type"]

      case type
      when "AWS::EMR::Cluster"
        raise "This component does not support multiple #{type} resources" unless @cluster.empty?

        @cluster[name] = resource
      when "AWS::EMR::InstanceGroupConfig"
        @instance_group_configs[name] = resource
      when "AWS::EMR::Step"
        @steps[name] = resource
      when "Pipeline::EMR::ScheduledAction"
        @scheduled_actions[name] = resource
      when "Pipeline::Features"
        @features[name] = resource
      when nil
        raise "Must specify a type for resource #{name.inspect}"
      else
        raise "Resource type #{type.inspect} is not supported by this component"
      end
    end

    raise "Must specify an AWS::EMR::Cluster resource" if @cluster.empty?

    @cluster_name = @cluster.keys[0]
  end

  # @see Consumable#sercurity_rules
  def security_items
    security_items = [
      {
        "Type" => "SecurityGroup",
        "Name" => "MasterSecurityGroup",
        "Component" => @component_name
      },
      {
        "Type" => "SecurityGroup",
        "Name" => "SlaveSecurityGroup",
        "Component" => @component_name
      },
      {
        "Type" => "SecurityGroup",
        "Name" => "xEmrMasterSecurityGroup",
        "Component" => @component_name
      },
      {
        "Type" => "SecurityGroup",
        "Name" => "xEmrSlaveSecurityGroup",
        "Component" => @component_name
      },
      {
        "Type" => "SecurityGroup",
        "Name" => "xEmrServiceSecurityGroup",
        "Component" => @component_name
      },
      {
        "Type" => "Role",
        "Name" => "InstanceRole",
        "Component" => @component_name,
        "ManagedPolicyArns" => Context.asir.managed_policy_arn
      }
    ]

    if @scheduled_actions.any?
      security_items += _emr_scheduled_action_security_items(
        component_name: @component_name
      )
    end

    return security_items
  end

  # @see Consumable#sercurity_rules
  def security_rules
    # Build the list of rules for each resource
    security_rules = []
    security_rules += _cluster_base_security_rules(@component_name)

    definition = @cluster.values.first

    mappings = {}
    mappings['read'] = %w(
      elasticmapreduce:List*
      elasticmapreduce:Describe*
    )

    # TODO: Decide if these should be available - EMR doesn't support resource-level or tag-based permissions
    # mappings["write"] = mappings["read"] + [ "elasticmapreduce:RunJobFlow" ]
    # mappings["admin"] = mappings["write"] + [ "elasticmapreduce:ModifyInstanceGroups" ]

    security_rules += _parse_security_rules(
      type: :auto,
      mappings: mappings,
      rules: definition["Security"],
      destination_ip: "#{@component_name}.MasterSecurityGroup",
      destination_iam: '*',
      condition_iam: {
        "StringEquals" => {
          "elasticmapreduce:ResourceTag/Name" => Defaults.component_name_tag(
            component_name: @component_name,
            build: Context.component.build_number(@component_name) || Defaults.sections[:build]
          )
        }
      }
    )

    if @scheduled_actions.any?
      security_rules += _emr_scheduled_action_security_rules(
        component_name: @component_name
      )
    end

    return security_rules
  end

  # @see Consumable#deploy
  def deploy
    # Upload required scripts
    _upload_cd_artefacts(component_name: @component_name)

    # Setup initial security rules for instance bootstrap
    _update_security_rules(rules: security_rules)

    # Create the stack
    stack_name = Defaults.component_stack_name(@component_name)
    tags = Defaults.get_tags(@component_name)
    @pipeline_features.map { |f| tags += f.feature_tags }
    template = _build_template
    Context.component.set_variables(@component_name, { "Template" => template })

    stack_outputs = {}
    begin
      stack_outputs = AwsHelper.cfn_create_stack(
        stack_name: stack_name,
        template: template,
        tags: tags
      )
    rescue ActionError => e
      stack_outputs = e.partial_outputs
      raise "Failed to create EMR stack - #{e}"
    ensure
      Context.component.set_variables(@component_name, stack_outputs)
    end

    # Create DNS name for this component
    # default to the cluster primary or master RDS instance endpoint
    return unless Defaults.ad_dns_zone?

    begin
      Log.debug "Deploying AD DNS records"

      dns_name = Defaults.deployment_dns_name(
        component: @component_name,
        zone: Defaults.ad_dns_zone
      )

      endpoint = Context.component.variable(
        @component_name,
        "#{@cluster_name}MasterPrivateIp"
      )

      deploy_ad_dns_records(
        dns_name: dns_name,
        endpoint: endpoint,
        type: 'A',
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

  # @see Consumable#teardown
  def teardown
    exception = nil

    # Delete component stack
    begin
      stack_id = Context.component.stack_id(@component_name)
      stack_name = Context.component.stack_name(@component_name)

      status = AwsHelper._cfn_get_stack_status(stack_name: stack_name)
      # Work around for removal of stacks previously failed to delete
      # Based on the common failue related to InstanceGroup configuration
      if status == 'DELETE_FAILED' && @instance_group_configs.keys.any?
        Log.debug "Removing #{stack_name}, retaining #{@instance_group_configs.keys}"
        instance_groups = @instance_group_configs.keys
        AwsHelper.cfn_delete_stack(stack_id, true, instance_groups) unless stack_id.nil?
      else
        AwsHelper.cfn_delete_stack(stack_id, true) unless stack_id.nil?
      end
    rescue => e
      exception ||= e
      Log.warn "Failed to delete component #{@component_name} stack #{stack_id.inspect} during teardown - #{e}"
    end

    begin
      AwsHelper.ec2_clear_security_group_rules(
        [
          Context.component.sg_id(@component_name, "xEmrServiceSecurityGroup"),
          Context.component.sg_id(@component_name, "xEmrMasterSecurityGroup"),
          Context.component.sg_id(@component_name, "xEmrSlaveSecurityGroup")
        ]
      )
    rescue => e
      exception ||= e
      Log.warn "Failed to clear security group rules during teardown - #{e}"
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

  # Generates base template for EMR cluster component
  # @return [Hash] Template for emr component
  def _build_template
    template = { "Resources" => {}, "Outputs" => {} }

    master_security_group_ids = [
      Context.component.sg_id(@component_name, "MasterSecurityGroup"),
      Context.asir.source_sg_id
    ]

    master_security_group_ids << Context.asir.destination_sg_id if @definition["IngressPoint"]

    slave_security_group_ids = [
      Context.component.sg_id(
        @component_name,
        "SlaveSecurityGroup"
      ),
      Context.asir.source_sg_id
    ]

    _process_instance_profile(
      template: template,
      instance_role_name: Context.component.role_name(
        @component_name,
        "InstanceRole"
      )
    )

    _process_emr_cluster(
      template: template,
      cluster_definition: @cluster,
      component_name: @component_name,
      job_role: { "Ref" => "InstanceProfile" },
      master_security_group_id: Context.component.sg_id(
        @component_name,
        "xEmrMasterSecurityGroup"
      ),
      slave_security_group_id: Context.component.sg_id(
        @component_name,
        "xEmrSlaveSecurityGroup"
      ),
      service_security_group_id: Context.component.sg_id(
        @component_name,
        "xEmrServiceSecurityGroup"
      ),
      additional_master_security_group_ids: master_security_group_ids,
      additional_slave_security_group_ids: slave_security_group_ids
    )

    _process_emr_steps(
      template: template,
      step_definitions: @steps,
      component_name: @component_name,
      cluster_name: @cluster_name,
    )

    _process_emr_instance_group_configs(
      template: template,
      instance_group_config_definitions: @instance_group_configs,
      cluster_name: @cluster_name,
      component_name: @component_name,
    )

    if @scheduled_actions.any?
      _process_emr_scheduled_actions(
        template: template,
        scheduled_actions: _parse_emr_scheduled_action(
          cluster: { "Ref" => @cluster_name },
          definitions: @scheduled_actions
        ),
        execution_role_arn: Context.component.role_arn(
          component_name,
          "EMRScalingExecutionRole"
        )
      )
    end

    unless Defaults.ad_dns_zone?
      _process_deploy_r53_dns_records(
        template: template,
        component_name: @component_name,
        zone: Defaults.r53_hosted_zone,
        resource_records: [_sub_master_dns_for_ip(cluster: @cluster_name)],
        ttl: '60',
        type: 'A'
      )
    end

    return template
  end
end
