require 'consumable'
require 'util/nsupdate'
require_relative 'builders/sns_topic_builder'
require_relative 'builders/route53_record_builder'
require_relative 'builders/dns_record_builder'

# Class is responsible for building AWS::SNS::Topic CloudFormation resource
class AwsSnsTopic < Consumable
  include SnsTopicBuilder
  include Route53RecordBuilder
  include DnsRecordBuilder

  # @param (see Consumable#initialize)
  def initialize(component_name, definition)
    super(component_name, definition)

    @topic = {}

    # Load resources from the component definition
    (definition["Configuration"] || {}).each do |name, resource|
      type = resource["Type"]

      case type
      when 'AWS::SNS::Topic'
        raise "This component does not support multiple #{type} resources" unless @topic.empty?

        @topic[name] = resource
      when 'Pipeline::Features'
        @features[name] = resource
      when nil
        raise "Must specify a type for resource #{name.inspect}"
      else
        raise "Resource type #{type.inspect} is not supported by this component"
      end
    end

    raise "Must specify an AWS::SNS::Topic resource" if @topic.empty?

    @topic_name = @topic.keys.first
  end

  # @return (see Consumable#security_items)
  def security_items
    []
  end

  # @return (see Consumable#security_rules)
  def security_rules
    name, definition = @topic.first
    security_rules = []

    mappings = {}
    mappings["read"] = %w(
      sns:Describe*
      sns:List*
    )

    mappings["write"] = mappings["read"] + %w(
      sns:Publish*
    )

    security_rules += _parse_security_rules(
      type: :iam,
      mappings: mappings,
      rules: definition['Security'],
      destination: Context.component.variable(@component_name, "#{name}Arn", nil)
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
        "#{@topic_name}Arn"
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

    # Clean up deployment DNS record
    begin
      _clean_ad_deployment_dns_record(@component_name)
    rescue => e
      exception ||= e
      Log.warn "Failed to remove the deployment AD DNS records during teardown - #{e}"
    end

    # Clean up release DNS record
    begin
      _clean_ad_release_dns_record(@component_name)
    rescue => e
      exception ||= e
      Log.warn "Failed to remove the release AD DNS records during teardown - #{e}"
    end

    raise exception unless exception.nil?
  end

  private

  # Builds out AWS::SNS::Topic CloudFormation template
  # @return [Hash] CloudFormation template representation
  def _build_template
    template = { "Resources" => {}, "Outputs" => {} }

    _process_sns_topic(
      template: template,
      definitions: @topic
    )

    sns_source_acocunts = [Context.environment.account_id]
    sns_source_acocunts += Context.environment.variable('sns_source_accounts', [])
    if sns_source_acocunts.any?

      _process_sns_topic_policy(
        template: template,
        source_accounts: sns_source_acocunts,
        definitions: {
          "#{@topic_name}SourceAccountsPolicy" => {
            'Properties' => {
              'Topics' => [{ 'Ref' => @topic_name }]
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
        resource_records: [JsonTools.hash_to_cfn_join('Ref' => @topic_name)],
        type: 'TXT',
        ttl: '60'
      )
    end

    template
  end
end
