require "consumable"
require_relative "builders/route53_record_builder"
require_relative "builders/sqs_queue_builder"
require_relative "builders/sns_topic_builder"
require_relative 'builders/dns_record_builder'

# Module is responsible for building AWS::SQS::Queue CloudFormation resource
class AwsSqs < Consumable
  include SqsQueueBuilder
  include SnsTopicBuilder
  include Route53RecordBuilder
  include DnsRecordBuilder

  # @param (see Consumable#initialize)
  def initialize(component_name, definition)
    super(component_name, definition)

    @queue = {}
    @sns_subscription = {}

    # Load resources from the component definition
    (definition["Configuration"] || {}).each do |name, resource|
      type = resource["Type"]

      case type
      when "AWS::SQS::Queue"
        raise "This component does not support multiple #{type} resources" unless @queue.empty?

        @queue[name] = resource
      when 'AWS::SNS::Subscription'
        @sns_subscription[name] = resource
      when "Pipeline::Features"
        @features[name] = resource
      when nil
        raise "Must specify a type for resource #{name.inspect}"
      else
        raise "Resource type #{type.inspect} is not supported by this component"
      end
    end

    raise "Must specify an AWS::SQS::Queue resource" if @queue.empty?

    @queue_name = @queue.keys.first
  end

  # @return (see Consumable#security_items)
  def security_items
    []
  end

  # @return (see Consumable#security_rules)
  def security_rules
    definition = @queue.values.first
    security_rules = []

    mappings = {}
    mappings["read"] = %w(
      sqs:ChangeMessageVisibility
      sqs:ChangeMessageVisibilityBatch
      sqs:DeleteMessage
      sqs:DeleteMessageBatch
      sqs:GetQueueAttributes
      sqs:GetQueueUrl
      sqs:ReceiveMessage
    )

    mappings["write"] = mappings["read"] + %w(
      sqs:SendMessage
      sqs:SendMessageBatch
    )

    mappings["admin"] = mappings["write"] + %w(
      sqs:SetQueueAttributes
      sqs:PurgeQueue
    )

    security_rules += _parse_security_rules(
      type: :iam,
      mappings: mappings,
      rules: definition["Security"],
      destination: Context.component.variable(@component_name, "#{@queue_name}Arn", nil),
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
    return unless Defaults.ad_dns_zone?

    begin
      Log.debug "Deploying AD DNS records"

      dns_name = Defaults.deployment_dns_name(
        component: component_name,
        zone: Defaults.ad_dns_zone
      )

      endpoint = Context.component.variable(
        @component_name,
        "#{@queue_name}Arn"
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

  # Execture release for the component
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

  # Builds out AWS::Kinesis::Stream CloudFormation template
  # @return [Hash] CloudFormation template representation
  def _build_template
    template = { "Resources" => {}, "Outputs" => {} }
    _process_queue(
      template: template,
      queue_definition: @queue
    )

    sns_topic_arns = []
    @sns_subscription.each do |name, definition|
      topic_arn = Context.component.replace_variables(
        JsonTools.get(definition, 'Properties.TopicArn')
      )
      sns_topic_arns.push(topic_arn)

      delivery_policy = JsonTools.get(definition, 'Properties.DeliveryPolicy', {})
      filter_policy = JsonTools.get(definition, 'Properties.FilterPolicy', {})

      _process_sns_subscription(
        template: template,
        definitions: {
          "#{name}SnsSubscription" => {
            'Type' => 'AWS::SNS::Subscription',
            'Properties' => {
              'Endpoint' => { 'Fn::GetAtt' => [@queue_name, 'Arn'] },
              'Protocol' => 'sqs',
              'TopicArn' => topic_arn,
              'DeliveryPolicy' => delivery_policy,
              'FilterPolicy' => filter_policy
            }
          }
        }
      )
    end

    if sns_topic_arns.any?
      _process_sqs_queue_policy(
        template: template,
        definitions: {
          "#{@queue_name}QueuePolicy" => {
            "Properties" => {
              'Queues' => [{ "Ref" => @queue_name }],
              'PolicyDocument' => {
                'Version' => '2012-10-17',
                'Id' => "#{@queue_name}QueuePolicy",
                'Statement' => [
                  {
                    'Effect' => 'Allow',
                    'Principal' => '*',
                    'Action' => %w(sqs:SendMessage),
                    'Resource' => '*',
                    'Condition' => { 'ArnEquals' => { 'aws:SourceArn' => sns_topic_arns } }
                  }
                ]
              }
            }
          }
        }
      )
    end

    unless Defaults.ad_dns_zone?
      _process_deploy_r53_dns_records(
        template: template,
        component_name: @component_name,
        zone: Defaults.r53_hosted_zone,
        resource_records: [JsonTools.hash_to_cfn_join('Fn::GetAtt' => [@queue_name, 'Arn'])],
        type: 'TXT',
        ttl: '60'
      )
    end

    return template
  end
end
