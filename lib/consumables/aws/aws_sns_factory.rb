require 'consumable'
require_relative 'builders/sns_factory_builder'

class AwsSnsFactory < Consumable
  include SnsFactoryBuilder

  # @param (see Consumable#initialize)
  def initialize(component_name, definition)
    super(component_name, definition)

    @sns_factory = {}

    # Load resources from the component definition
    (definition['Configuration'] || {}).each do |name, resource|
      type = resource['Type']

      case type
      when 'Pipeline::SNS::Factory'
        raise "This component does not support multiple #{type} resources" unless @sns_factory.empty?

        @sns_factory[name] = resource
      when 'Pipeline::Features'
        @features[name] = resource
      when nil
        raise "Must specify a type for resource #{name.inspect}"
      else
        raise "Resource type #{type.inspect} is not supported by this component"
      end
    end

    @sns_factory_name = @sns_factory.keys.first
    # Assign default names to unspecified resources
    raise 'Component requires at least one resource of type Pipeline::SNS::Factory' if @sns_factory.empty?
  end

  # @return (see Consumable#security_items)
  def security_items
    [
      {
        'Name' => 'LambdaExecutionRole',
        'Type' => 'Role',
        'Component' => @component_name,
        'Service' => 'lambda.amazonaws.com'
      }
    ]
  end

  # @return (see Consumable#security_rules)
  def security_rules
    definition = @sns_factory.values.first
    security_rules = []

    mappings = {}
    mappings["read"] = %w(
      sns:ListSubscriptionsByTopic
    )

    mappings["write"] = mappings["read"] + %w(
      sns:Subscribe
      sns:Unsubscribe
      sns:Publish
      sns:CreateTopic
      sns:DeleteTopic
      sns:GetTopicAttributes
      sns:SetTopicAttributes
      sns:ConfirmSubscription
    )

    security_rules += _parse_security_rules(
      type: :iam,
      mappings: mappings,
      rules: definition['Security'],
      destination: "#{Context.component.variable(@component_name, "#{@sns_factory_name}TopicArnPrefix")}*"
    )

    list_mappings = {
      'read' => %w(
        sns:ListTopics
        sns:ListSubscriptions
      ),
      'write' => %w(
        sns:ListTopics
        sns:ListSubscriptions
      )
    }

    security_rules += _parse_security_rules(
      type: :iam,
      mappings: list_mappings,
      rules: definition['Security'],
      destination: '*'
    )

    create_app_endpoint_mappings = {
      'write' => %w(
        sns:CreatePlatformEndpoint
        sns:DeleteEndpoint
        sns:Publish
        sns:SetEndpointAttributes
        sns:ListEndpointsByPlatformApplication
      )
    }

    security_rules += _parse_security_rules(
      type: :iam,
      mappings: create_app_endpoint_mappings,
      rules: definition['Security'],
      destination: "#{Context.component.variable(@component_name, "#{@sns_factory_name}PlatformAppArnPrefix")}*"
    )

    create_publish_endpoint_mappings = {
      'write' => %w(sns:Publish)
    }

    security_rules += _parse_security_rules(
      type: :iam,
      mappings: create_publish_endpoint_mappings,
      rules: definition['Security'],
      destination: "#{Context.component.variable(@component_name, "#{@sns_factory_name}PlatformEndpointArnPrefix")}*"
    )
    # Delete Topics permissions for Custom Resource Lambda
    security_rules += _delete_topics_lambda_security_rules(
      component_name: @component_name,
      execution_role_name: 'LambdaExecutionRole',
      prefix_arn: Context.component.variable(@component_name, "#{@sns_factory_name}TopicArnPrefix")
    )

    return security_rules
  end

  def _platform_app_endpoint_prefix
    sections = Defaults.sections
    [
      sections[:ams],
      sections[:qda]
    ].join('-').gsub(/[^a-zA-Z0-9\-]/, '-')
  end

  def _platform_app_endpoint_arn_prefix(scope)
    [
      'arn:aws:sns:',
      Context.environment.region,
      ':',
      Context.environment.account_id,
      ":#{scope}/*/",
      _platform_app_endpoint_prefix
    ].join('')
  end

  def _factory_prefix
    sections = Defaults.sections
    [
      sections[:ams],
      sections[:qda],
      sections[:as],
      sections[:ase],
      sections[:branch],
      sections[:build],
      @component_name # factory.yaml
    ].join('-').gsub(/[^a-zA-Z0-9\-]/, '-')
  end

  def _factory_arn_prefix
    [
      'arn:aws:sns',
      Context.environment.region,
      Context.environment.account_id,
      _factory_prefix
    ].join(':')
  end

  # Execute deployment steps for the component
  def deploy
    # Deploy stack
    Log.info "Creating stack"
    stack_name = Defaults.component_stack_name(@component_name)
    tags = Defaults.get_tags(@component_name)
    @pipeline_features.map { |f| tags += f.feature_tags }
    template = _full_template

    begin
      stack_outputs = {}
      stack_outputs = AwsHelper.cfn_create_stack(
        stack_name: stack_name,
        template: template,
        tags: tags
      )
      Context.component.set_variables(
        @component_name,
        "#{@sns_factory_name}PlatformAppArnPrefix" => _platform_app_endpoint_arn_prefix('app'),
        "#{@sns_factory_name}PlatformEndpointArnPrefix" => _platform_app_endpoint_arn_prefix('endpoint'),
        "#{@sns_factory_name}TopicPrefix" => _factory_prefix,
        "#{@sns_factory_name}TopicArnPrefix" => _factory_arn_prefix
      )
    rescue => e
      stack_outputs = e.is_a?(ActionError) ? e.partial_outputs : {}
      raise "Failed to create stack - #{e}"
    ensure
      Context.component.set_variables(@component_name, stack_outputs)
    end
  end

  # Execute release for the component
  def release
    super
  end

  # Execute teardown for the component stack
  def teardown
    exception = nil

    # Delete stack
    begin
      stack_id = Context.component.stack_id(@component_name)
      AwsHelper.cfn_delete_stack(stack_id) unless stack_id.nil?
    rescue => e
      exception ||= e
      Log.warn "Failed to delete stack #{stack_id.inspect} during teardown - #{e}"
    end

    begin
      Log.debug "Here is where we could delete all topics with the factory Prefix"
    rescue => e
      exception ||= e
      Log.error "Failed to delete SNS topics"
    end

    raise exception unless exception.nil?
  end

  private

  def _full_template
    template = { 'Resources' => {}, 'Outputs' => {} }

    _process_sns_factory(
      template: template,
      prefix: _factory_prefix,
      execution_role_arn: Context.component.role_arn(@component_name, 'LambdaExecutionRole')
    )

    return template
  end
end
