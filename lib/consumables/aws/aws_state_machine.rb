require "consumable"
require_relative "builders/step_functions_state_machine_builder"
require_relative "builders/step_functions_activity_builder"
require_relative "builders/events_rule_builder"
require_relative 'builders/lambda_function_builder'
require_relative "builders/security_rule_builder"
require_relative "builders/dns_record_builder"
require_relative "builders/logs_subscriptionfilter_builder"

# Class is responsible for building AWS Step Functions resources
class AwsStateMachine < Consumable
  include StepFunctionsStateMachineBuilder
  include StepFunctionsActivityBuilder
  include EventsRuleBuilder
  include LambdaFunctionBuilder
  include SecurityRuleBuilder
  include DnsRecordBuilder
  include LogsSubscriptionFilterBuilder

  # @param (see Consumable#initialize)
  def initialize(component_name, definition)
    super(component_name, definition)

    @state_machine = {}
    @step_functions_activity = {}
    @lambda_function = {}
    @logs_subscription_filter = {}
    @events_rule = {}

    # Load resources from the component definition
    (definition["Configuration"] || {}).each do |name, resource|
      type = resource["Type"]

      case type
      when 'AWS::StepFunctions::StateMachine'
        raise "This component does not support multiple #{type} resources" unless @state_machine.empty?

        @state_machine[name] = resource
      when 'AWS::StepFunctions::Activity'
        @step_functions_activity[name] = resource
      when 'AWS::Lambda::Function'
        @lambda_function[name] = resource
      when 'AWS::Logs::SubscriptionFilter'
        @logs_subscription_filter[name] = resource
      when 'AWS::Events::Rule'
        @events_rule[name] = resource
      when 'Pipeline::Features'
        @features[name] = resource
      else
        raise "Resource type #{type.inspect} is not supported by this component"
      end
    end

    raise "Must specify an AWS::StepFunctions::StateMachine resource" if @state_machine.empty?

    @state_machine_name = @state_machine.keys.first
    @state_machine_definition = JsonTools.get(@state_machine.values.first, "Properties.DefinitionString", [])
  end

  # @return (see Consumable#security_items)
  def security_items
    security_items = []

    if @lambda_function.any?
      security_items += [
        {
          "Name" => "SecurityGroup",
          "Type" => "SecurityGroup",
          "Component" => @component_name
        },
        {
          "Name" => "ExecutionRole",
          "Type" => "Role",
          "Component" => @component_name,
          "Service" => "lambda.amazonaws.com",
          "ManagedPolicyArns" => Context.asir.managed_policy_arn
        }
      ]
    end

    if @events_rule.any?

      security_items << {
        'Name' => 'EventsRole',
        'Type' => 'Role',
        'Component' => @component_name,
        'Service' => 'events.amazonaws.com'
      }
    end
    security_items
  end

  # @return (see Consumable#security_rules)
  def security_rules
    security_rules = []

    mappings = {}
    mappings['execute'] = %w(
      states:StartExecution
      states:StopExecution
    )

    mappings['read'] = mappings['execute'] + %w(
      states:Describe*
    )

    if @events_rule.any?
      security_rules << IamSecurityRule.new(
        roles: "#{@component_name}.EventsRole",
        actions: ['states:StartExecution'],
        resources: _resource_arns
      )
    end

    if @lambda_function.any?
      # Attach base profile and security group rules
      security_rules += _base_security_rules(
        component_name: @component_name,
        role_name: 'ExecutionRole'
      )
    end

    # Process access rules for other components
    security_rules += _parse_security_rules(
      type: :iam,
      mappings: mappings,
      rules: @state_machine.values.first["Security"],
      destination: _resource_arns
    )

    security_rules
  end

  # Execute deployment steps for the component
  def deploy
    # Create stack
    stack_name = Defaults.component_stack_name(@component_name)
    tags = Defaults.get_tags(@component_name)
    @pipeline_features.map { |f| tags += f.feature_tags }
    template = _build_template
    Context.component.set_variables(@component_name, "Template" => template)

    if @lambda_function.any?
      lambda_function_artefacts = []
      @lambda_function.each do |name, definition|
        lambda_function_artefacts << JsonTools.get(definition, 'Properties.Code', nil)

        # Unpack and upload specified lambda artefact package
        _upload_package_artefacts(
          component_name: @component_name,
          artefacts: lambda_function_artefacts.compact
        )
      end
      _update_security_rules(rules: security_rules)
    end

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

    return unless Defaults.ad_dns_zone?

    begin
      Log.debug "Deploying AD DNS records"

      dns_name = Defaults.deployment_dns_name(
        component: component_name,
        zone: Defaults.ad_dns_zone
      )

      endpoint = Context.component.variable(
        @component_name,
        "#{@state_machine_name}Arn"
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
      AwsHelper.cfn_delete_stack(stack_id) unless stack_id.nil?
    rescue => e
      exception ||= e
      Log.warn "Failed to delete stack #{stack_id.inspect} during teardown - #{e}"
    end

    # Clean up deployment DNS record
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

  # Builds out StepFunctions template
  # @return [Hash] CloudFormation template representation
  def _build_template
    template = { "Resources" => {}, "Outputs" => {} }

    _process_step_functions_activity(
      template: template,
      component_name: @component_name,
      definitions: @step_functions_activity
    )

    @lambda_function.each do |name, definition|
      _process_lambda_function(
        template: template,
        security_group_ids: [Context.component.sg_id(@component_name, "SecurityGroup"), Context.asir.source_sg_id],
        function_definition: { name => definition },
        role: Context.component.role_arn(@component_name, "ExecutionRole")
      )

      next unless @logs_subscription_filter.any?

      filter_name, definition = @logs_subscription_filter.first

      _process_logs_subscription_filter(
        template: template,
        log_group: { 'Ref' => "#{name}LogGroup" },
        definitions: { "#{filter_name}#{name}" => definition }
      )
    end

    resources = {}
    if @step_functions_activity.any?
      @step_functions_activity.keys.each { |name| resources[name] = { 'Ref' => name } }
    end

    if @lambda_function.any?
      @lambda_function.keys.each { |name| resources[name] = { 'Fn::GetAtt' => [name, 'Arn'] } }
    end

    _process_step_functions_state_machine(
      template: template,
      definitions: Context.component.replace_variables(@state_machine),
      resources: resources,
      role_arn: _states_execution_role
    )

    @events_rule.each do |name, definition|
      input = Context.component.replace_variables(
        JsonTools.get(definition, 'Properties.Pipeline::EventInput', {})
      )

      definition['Properties']['Targets'] = [{
        'Arn' => { 'Ref' => @state_machine_name },
        'Id' => @state_machine_name,
        'Input' => input
      }]

      _process_events_rule(
        template: template,
        events_role_arn: Context.component.role_arn(@component_name, "EventsRole"),
        definitions: { name => definition }
      )
    end

    unless Defaults.ad_dns_zone?
      _process_deploy_r53_dns_records(
        template: template,
        component_name: @component_name,
        zone: Defaults.r53_hosted_zone,
        resource_records: [JsonTools.hash_to_cfn_join("Ref" => @state_machine_name)],
        type: 'TXT',
        ttl: '60'
      )
    end

    template
  end

  # Returns the default StepFunctions service role for account/region
  # @return [String] Default step functions service role for the region
  def _states_execution_role
    %W(
      arn:aws:iam:
      #{Context.environment.account_id}
      role/service-role/StatesExecutionRole-#{Context.environment.region}
    ).join(':')
  end

  # Returns a list of resource ARNs applicable to this State Machine
  # @return [Array] Resource ARNs
  def _resource_arns
    state_machine_name = Context.component.variable(@component_name, "#{@state_machine_name}Name", nil)

    state_machine_arn = [
      'arn:aws:states',
      Context.environment.region,
      Context.environment.account_id,
      'stateMachine',
      state_machine_name
    ].join(':')

    state_machine_executions_arn = [
      'arn:aws:states',
      Context.environment.region,
      Context.environment.account_id,
      'execution',
      state_machine_name,
      '*'
    ].join(':')

    [state_machine_arn, state_machine_executions_arn]
  end
end
