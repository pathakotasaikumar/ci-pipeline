require "consumable"
require_relative "builders/dynamodb_table_builder"
require_relative "builders/route53_record_builder"
require_relative "builders/dynamodb_scheduled_action_builder"
require_relative "builders/pipeline_dynamodb_backup_policy_builder"
require_relative "builders/dns_record_builder"
require_relative "builders/application_autoscaling_builder"

class AwsDynamoDbTable < Consumable
  include DynamoDbTableBuilder
  include Route53RecordBuilder
  include DynamoDBScheduledActionBuilder
  include PipelineDynamoDBBackupPolicyBuilder
  include DnsRecordBuilder
  include ApplicationAutoscalingBuilder

  # @param (see Consumable#initialize)
  def initialize(component_name, definition)
    super(component_name, definition)

    @table = {}
    @scheduled_actions = {}
    @backup_policy = {}
    @scalable_target = {}
    @scaling_policy = {}
    @billing_type = {}
    # Load resources from the component definition
    (definition["Configuration"] || {}).each do |name, resource|
      type = resource["Type"]

      case type
      when "AWS::DynamoDB::Table"
        raise "This component does not support multiple #{type} resources" unless @table.empty?

        @table[name] = resource
        @billing_type = @table[name]["Properties"]
      when "Pipeline::DynamoDB::ScheduledAction"
        @scheduled_actions[name] = resource
      when "Pipeline::Features"
        @features[name] = resource
      when "AWS::ApplicationAutoScaling::ScalableTarget"
        @scalable_target[name] = resource
      when "AWS::ApplicationAutoScaling::ScalingPolicy"
        @scaling_policy[name] = resource
      when 'Pipeline::DynamoDB::BackupPolicy'
        @backup_policy[name] = resource
      when nil
        raise "Must specify a type for resource #{name.inspect}"
      else
        raise "Resource type #{type.inspect} is not supported by this component"
      end
    end

    raise "Must specify an AWS::DynamoDB::Table resource" if @table.empty?

    @table_name = @table.keys.first
  end

  # @return (see Consumable#security_items)
  def security_items
    security_items = []

    if @scheduled_actions.any?
      security_items += _dynamodb_scheduled_action_security_items(
        component_name: @component_name
      )
    end

    if @scalable_target.any?
      security_items << {
        "Name" => "AutoscalingScalingRole",
        "Type" => "Role",
        "Component" => @component_name,
        "Service" => "application-autoscaling.amazonaws.com"
      }
    end

    return security_items
  end

  # @return (see Consumable#security_rules)
  def security_rules
    definition = @table.values.first
    security_rules = []

    mappings = {}
    mappings["read"] = %w(
      dynamodb:BatchGetItem
      dynamodb:DescribeLimits
      dynamodb:DescribeTable
      dynamodb:GetItem
      dynamodb:Query
      dynamodb:Scan
      dynamodb:GetRecords
      dynamodb:GetShardIterator
      dynamodb:DescribeStream
    )

    # dynamodb:CreateTable exists to support KCL < 1.6.5 (used by EMR Spark)
    # which performs a CreateTable call to check if table exists
    mappings["write"] = mappings["read"] + %w(
      dynamodb:CreateTable
      dynamodb:BatchWriteItem
      dynamodb:DeleteItem
      dynamodb:PutItem
      dynamodb:UpdateItem
    )
    mappings["admin"] = mappings["write"] + %w(
      dynamodb:UpdateTable
    )

    destination = Context.component.variable(@component_name, "#{@table_name}Arn", nil)
    destination = "#{destination}*" unless destination.nil?
    security_rules += _parse_security_rules(
      type: :iam,
      mappings: mappings,
      rules: definition["Security"],
      destination: destination
    )
    if @scalable_target.any?
      security_rules += _dynamodb_autoscaling_security_rules(
        component_name: @component_name
      )
    end

    if @scheduled_actions.any?
      security_rules += _dynamodb_scheduled_action_security_rules(
        component_name: @component_name
      )
    end

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
        component: @component_name,
        zone: Defaults.ad_dns_zone
      )

      endpoint = Context.component.variable(
        @component_name,
        "#{@table_name}Arn"
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

  # Checking if Billing Type is set
  def _check_billing_type
    billing_modes = ["PAY_PER_REQUEST", "PROVISIONED"]
    if @billing_type.has_key? "BillingMode" and billing_modes.include? @billing_type["BillingMode"]
      Log.info "The DynamoDb billing mode is set to #{@billing_type["BillingMode"]}"
      if @billing_type["BillingMode"].eql? "PAY_PER_REQUEST" and @billing_type.has_key? "ProvisionedThroughput"
        raise "Error: The BillingMode is set to #{@billing_modes["BillingMode"]}. Please remove ProvisionedThroughput from the YAML configuration."
      elsif @billing_type["BillingMode"].eql? "PROVISIONED" and !@billing_type.has_key? "ProvisionedThroughput"
        raise "Error: The BillingMode is set to #{@billing_modes["BillingMode"]}. Please add ProvisionedThroughput from the YAML configuration."
      else
        return @billing_type["BillingMode"]
      end
    else
      Log.info "The DynamoDb billing mode is set to Default (PROVISIONED)."
      if @billing_type.has_key? "ProvisionedThroughput"
        return "PROVISIONED"
      else
        raise "The BillingMode is set to PROVISIONED as a default value, but missing ProvisionedThroughput tag.\nPlease correct the YAML configuration."
      end
    end
  end

  # Builds out AWS::DynamoDB::Table CloudFormation template
  # @return [Hash] CloudFormation template representation
  def _build_template
    billing_mode = _check_billing_type
    template = { "Resources" => {}, "Outputs" => {} }
    _process_dynamodb_table(
      template: template,
      table_definition: @table,
      component_name: @component_name,
      billing_mode: billing_mode
    )

    if @scheduled_actions.any?
      _process_dynamodb_scheduled_actions(
        template: template,
        scheduled_actions: _parse_dynamodb_scheduled_action(
          definitions: @scheduled_actions
        ),
        execution_role_arn: Context.component.role_arn(
          component_name,
          "DynamoDBScalingExecutionRole"
        )
      )
    end

    if @scalable_target.any?
      _process_application_autoscaling_group(
        template: template,
        component_name: @component_name,
        scalable_target: @scalable_target,
        scaling_policy: @scaling_policy,
        service_name_space: 'dynamodb',
        service_role_arn: Context.component.role_arn(@component_name, "AutoscalingScalingRole"),
      )
    end

    if @backup_policy.any?

      policy_definitions = _parse_dynamodb_backup_policy(
        resource_id: { 'Ref' => @table_name },
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
        resource_records: [{
          "Fn::Join" => ["", [
            "\"",
            "arn:aws:dynamodb:",
            { "Ref" => "AWS::Region" },
            ":",
            { "Ref" => "AWS::AccountId" },
            ":table/",
            { "Ref" => @table_name },
            "\""
          ]]
        }],
        ttl: '60',
        type: 'TXT'
      )
    end

    return template
  end
end
