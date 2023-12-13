require_relative '../../consumable'
require_relative "builders/alarm_builder"
require_relative "builders/application_autoscaling_builder"
require_relative 'builders/ecs_events_rule_builder'
require_relative 'builders/ecs_service_builder'
require_relative 'builders/security_rule_builder'
require_relative 'builders/task_definition_builder'

# @attr_reader scalable_target [String] name of scalable_target resource
class AwsECSTask < Consumable
  include AlarmBuilder
  include ApplicationAutoscalingBuilder
  include ECSEventsRuleBuilder
  include ECSServiceBuilder
  include SecurityRuleBuilder
  include TaskDefinitionBuilder

  attr_reader :scalable_target

  # @param (see Consumable#initialize)
  def initialize(component_name, definition)
    super(component_name, definition)
    #raise "This feature is experimental. Please enquire with QCP in order to activate it." unless Context.environment.experimental?

    @alarms = {}
    @ecs_service = {}
    @events_rule = {}
    @scalable_target = {}
    @scaling_policy = {}
    @task_definition = {}

    # Load resources from the component definition
    (definition['Configuration'] || {}).each do |name, resource|
      type = resource['Type']

      case type
      when "AWS::CloudWatch::Alarm"
        @alarms[name] = resource
      when "AWS::ApplicationAutoScaling::ScalableTarget"
        @scalable_target[name] = resource
      when "AWS::ApplicationAutoScaling::ScalingPolicy"
        @scaling_policy[name] = resource
      when 'AWS::ECS::TaskDefinition'
        raise 'Multiple AWS::ECS::TaskDefinition resources found' if @task_definition.any?

        @task_definition[name] = resource
      when 'AWS::ECS::Service'
        raise 'Multiple AWS::ECS::Service resources found' if @ecs_service.any?

        @ecs_service[name] = resource
      when 'AWS::Events::Rule'
        @events_rule[name] = resource
      when 'Pipeline::Features'
        @features[name] = resource
      else
        raise "Resource type #{type.inspect} is not supported by this component"
      end
    end
  end

  # @return (see Consumable#security_items)
  def security_items
    security_items = [
      {
        "Name" => "SecurityGroup",
        "Type" => "SecurityGroup",
        "Component" => @component_name
      },
      {
        "Name" => "ExecutionRole",
        "Type" => "Role",
        "Component" => @component_name,
        "Service" => "ecs-tasks.amazonaws.com"
      },
      {
        "Name" => "TaskRole",
        "Type" => "Role",
        "Component" => @component_name,
        "Service" => "ecs-tasks.amazonaws.com",
        "ManagedPolicyArns" => Context.asir.managed_policy_arn
      }
    ]
    return security_items
  end

  # @return (see Consumable#security_rules)
  def security_rules
    security_rules = []

    # Attach base profile and security group rules
    security_rules += _execution_base_security_rules(
      component_name: @component_name,
      role_name: 'ExecutionRole'
    )

    security_rules += _task_base_security_rules(
      component_name: @component_name,
      role_name: 'TaskRole'
    )

    # Process access rules for other components
    security_rules += _parse_security_rules(
      type: :ip,
      rules: @task_definition.values.first["Security"],
      destination: "#{@component_name}.SecurityGroup",
    )

    return security_rules
  end

  def deploy
    # Create security groups
    _update_security_rules(rules: security_rules)

    stack_name = Defaults.component_stack_name(@component_name)
    tags = Defaults.get_tags(@component_name)
    @pipeline_features.map { |f| tags += f.feature_tags }
    template = _full_template(tags: tags)

    stack_outputs = {}
    begin
      stack_outputs = AwsHelper.cfn_create_stack(
        stack_name: stack_name,
        template: template,
        tags: tags
      )
    rescue ActionError => e
      stack_outputs = e.is_a?(ActionError) ? e.partial_outputs : {}
      raise "Failed to create stack - #{e}"
    ensure
      Context.component.set_variables(@component_name, stack_outputs)
    end
  end

  def release
    super
  end

  def teardown
    exception = nil

    # Delete component stack
    begin
      stack_id = Context.component.stack_id(@component_name)
      AwsHelper.cfn_delete_stack(stack_id) unless stack_id.nil?
    rescue => e
      exception ||= e
      Log.warn "Failed to delete stack #{stack_id.inspect} during teardown - #{e}"
    end

    raise exception unless exception.nil?
  end

  # @return [Hash] Deploy and Release ARNs for the component
  def name_records
    {}
  end

  private

  def _full_template(
    tags: nil
  )
    template = { "Resources" => {}, "Outputs" => {} }
    _process_task_definition(
      component_name: @component_name,
      template: template,
      task_definition: @task_definition,
      tags: tags,
    )

    if @ecs_service.any?
      resource_id = _process_ecs_service(
        template: template,
        component_name: @component_name,
        task_definition_logical_name: @task_definition.keys[0],
        service_definition: @ecs_service,
      )

      # Pull back out the cluster name
      service_name = @ecs_service.keys[0]

      if @scalable_target.any? or @scaling_policy.any?
        _process_application_autoscaling_group(
          template: template,
          component_name: @component_name,
          scalable_target: @scalable_target,
          scaling_policy: @scaling_policy,
          service_name_space: 'ecs',
          resource_id: resource_id
        )
      end

      # Generate Alarm resources
      @alarms.each do |name, definition|
        namespace = JsonTools.get(definition, "Properties.Namespace", "AWS/ECS")
        definition["Properties"]["Namespace"] = namespace

        if namespace == "AWS/ECS"
          # Auto populate the dimension if it falls under the current namespace of AWS/ECS
          definition["Properties"]["Dimensions"] = JsonTools.get(definition, "Properties.Dimensions", [
                                                                   {
                                                                     "Name" => "ServiceName",
                                                                     "Value" => { "Fn::GetAtt" => [service_name, "Name"] }
                                                                   },
                                                                   {
                                                                     "Name" => "ClusterName",
                                                                     "Value" => template["Resources"][service_name]["Properties"]["Cluster"]
                                                                   },
                                                                 ])
        end
      end
      _process_alarms(
        template: template,
        alarm_definitions: @alarms,
      )

    else
      @events_rule.each do |name, definition|
        _process_ecs_events_rule(
          component_name: @component_name,
          rule_name: name,
          template: template,
          task_definition_logical_name: @task_definition.keys[0],
          event_definition: definition
        )
      end
    end

    return template
  end
end
