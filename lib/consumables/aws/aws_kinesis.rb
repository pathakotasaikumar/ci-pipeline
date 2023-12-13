require "consumable"
require_relative "builders/kinesis_stream_builder"
require_relative "builders/logs_destination_builder"
require_relative "builders/route53_record_builder"
require_relative 'builders/dns_record_builder'

# Class is responsible for building AWS::Kinesis::Stream CloudFormation resource
class AwsKinesis < Consumable
  include KinesisStreamBuilder
  include LogsDestinationBuilder
  include Route53RecordBuilder
  include DnsRecordBuilder

  # @param (see Consumable#initialize)
  def initialize(component_name, definition)
    super(component_name, definition)

    @stream = {}
    @destination = {}

    # Load resources from the component definition
    (definition["Configuration"] || {}).each do |name, resource|
      type = resource["Type"]

      case type
      when "AWS::Kinesis::Stream"
        raise "This component does not support multiple #{type} resources" unless @stream.empty?

        @stream[name] = resource
      when "AWS::Logs::Destination"
        @destination[name] = resource
      when "Pipeline::Features"
        @features[name] = resource
      when nil
        raise "Must specify a type for resource #{name.inspect}"
      else
        raise "Resource type #{type.inspect} is not supported by this component"
      end
    end

    raise "Must specify an AWS::Kinesis::Stream resource" if @stream.empty?

    # Update user defined retention period
    @retention_period = JsonTools.get(@stream.values.first, "Properties.Pipeline::RetentionPeriod", nil)
    unless @retention_period.nil? || (24..168).cover?(@retention_period)
      raise "Pipeline::RetentionPeriod must be between 24 hours and 168 hours (1 to 7 days)"
    end

    @stream_name = @stream.keys.first
  end

  # @return (see Consumable#security_items)
  def security_items
    security_items = []

    if @destination.any?
      security_items << {
        'Name' => 'LogsDestinationRole',
        'Type' => 'Role',
        'Component' => @component_name,
        'Service' => 'logs.amazonaws.com'
      }
    end

    security_items
  end

  # @return (see Consumable#security_rules)
  def security_rules
    name, definition = @stream.first
    security_rules = []

    mappings = {}
    mappings["read"] = %w(
      kinesis:DescribeStream
      kinesis:GetRecords
      kinesis:GetShardIterator
    )

    mappings["write"] = mappings["read"] + %w(
      kinesis:PutRecord
      kinesis:PutRecords
    )

    mappings["admin"] = mappings["write"] + %w(
      kinesis:DecreaseStreamRetentionPeriod
      kinesis:IncreaseStreamRetentionPeriod
      kinesis:MergeShards
      kinesis:SplitShard
    )

    security_rules += _parse_security_rules(
      type: :iam,
      mappings: mappings,
      rules: definition["Security"],
      destination: Context.component.variable(@component_name, "#{name}Arn", nil),
    )

    if @destination.any?

      stream_arn = Context.component.variable(@component_name, "#{name}Arn", nil)

      security_rules << IamSecurityRule.new(
        roles: "#{@component_name}.LogsDestinationRole",
        actions: %w(kms:GenerateDataKey),
        resources: Context.kms.secrets_key_arn
      )

      security_rules << if stream_arn.nil?
                          IamSecurityRule.new(
                            roles: "#{@component_name}.LogsDestinationRole",
                            actions: %w(kinesis:PutRecord),
                            resources: '*'
                          )
                        else
                          IamSecurityRule.new(
                            roles: "#{@component_name}.LogsDestinationRole",
                            actions: %w(kinesis:PutRecord),
                            resources: stream_arn
                          )
                        end
    end

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

    # Update security group up front to ensure we have a role that can write to the stream
    # After deploy the role is reduced to only target specific Kinesis role arn
    _update_security_rules(rules: security_rules) if @destination.any?

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

    unless @retention_period.nil?
      Log.debug "Setting retention period to #{@retention_period}"
      AwsHelper.kinesis_set_retention_period_hours(
        stream_name: Context.component.variable(@component_name, "#{@stream_name}Name"),
        retention_period_hours: @retention_period.to_i
      )
    end
    return unless Defaults.ad_dns_zone?

    begin
      Log.debug "Deploying AD DNS records"

      deploy_ad_dns_records
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
      _clean_ad_release_dns_record(@component_name)
    rescue => e
      exception ||= e
      Log.warn "Failed to remove AD DNS records during teardown - #{e}"
    end

    raise exception unless exception.nil?
  end

  # Create release DNS records in AD DNS zone
  def create_ad_release_dns_records(component_name:)
    dns_name = Defaults.release_dns_name(
      component: component_name,
      zone: Defaults.ad_dns_zone
    )

    # Obtain DNS deployment dns name from context
    endpoint = Context.component.variable(component_name, 'DeployDnsName')
    Util::Nsupdate.create_dns_record(dns_name, endpoint, "CNAME", 60)

    Log.output "#{component_name} DNS: #{dns_name}" if Defaults.ad_dns_zone?

    @destination.each do |destination_name, definition|
      destination_name = @destination.keys.first

      # Create DNS name for this component
      dns_name = Defaults.release_dns_name(
        component: @component_name,
        resource: destination_name,
        zone: Defaults.ad_dns_zone
      )

      # Obtain DNS deployment dns name from context
      endpoint = Context.component.variable(@component_name, "#{destination_name}DeployDnsName")
      Util::Nsupdate.create_dns_record(dns_name, endpoint, "CNAME", 60)

      Log.output "#{@component_name} DNS: #{dns_name}" if Defaults.ad_dns_zone?
    end
  end

  # Generates template for Route53 Release record based on the component name
  # @param template [Hash] CloudFormation template reference
  def process_release_r53_dns_record(
    template:,
    zone:,
    component_name:
  )
    dns_name = Defaults.release_dns_name(
      component: component_name,
      zone: Defaults.dns_zone
    )

    _process_route53_records(
      template: template,
      record_sets: {
        "#{component_name}ReleaseDns".gsub(/[^a-zA-Z0-9]/, '') => {
          "Properties" => {
            "Name" => dns_name,
            "Type" => "CNAME",
            "TTL" => "60",
            "ResourceRecords" => [
              Context.component.variable(component_name, 'DeployDnsName')
            ]
          }
        }
      }
    )
    Log.output "#{@component_name} DNS: #{dns_name}"

    @destination.each do |destination_name, definition|
      dns_name = Defaults.release_dns_name(
        component: component_name,
        resource: destination_name,
        zone: Defaults.dns_zone
      )

      _process_route53_records(
        template: template,
        record_sets: {
          "#{component_name}#{destination_name}ReleaseDns".gsub(/[^a-zA-Z0-9]/, '') => {
            "Properties" => {
              "Name" => dns_name,
              "Type" => "CNAME",
              "TTL" => "60",
              "ResourceRecords" => [
                Context.component.variable(component_name, "#{destination_name}DeployDnsName")
              ]
            }
          }
        }
      )
      Log.output "#{component_name} DNS: #{dns_name}"
    end
  end

  # @return [Hash] Deploy and Release DNS records for the component
  def name_records
    name_records = {
      'DeployDnsName' => Defaults.deployment_dns_name(
        component: component_name,
        zone: Defaults.dns_zone
      ),
      'ReleaseDnsName' => Defaults.release_dns_name(
        component: component_name,
        zone: Defaults.dns_zone
      )
    }

    if @destination.any?
      destination_name = @destination.keys.first
      name_records["#{destination_name}DeployDnsName"] = Defaults.deployment_dns_name(
        component: @component_name,
        resource: destination_name,
        zone: Defaults.dns_zone
      )

      name_records["#{destination_name}ReleaseDnsName"] = Defaults.release_dns_name(
        component: @component_name,
        resource: destination_name,
        zone: Defaults.dns_zone
      )
    end
    name_records
  end

  private

  # Builds out AWS::Kinesis::Stream CloudFormation template
  # @return [Hash] CloudFormation template representation
  def _build_template
    template = { "Resources" => {}, "Outputs" => {} }

    _process_kinesis_stream(
      template: template,
      stream: @stream,
      component_name: @component_name,
    )

    @destination.each do |name, definition|
      shared_accounts = [Context.environment.account_id]
      shared_accounts += Context.environment.variable('log_destination_source_accounts', [])

      _process_logs_destination(
        template: template,
        source_accounts: shared_accounts,
        role_arn: Context.component.role_arn(@component_name, 'LogsDestinationRole'),
        definitions: {
          name => {
            'Properties' => {
              'TargetArn' => { 'Fn::GetAtt' => [@stream_name, 'Arn'] }
            }
          }
        }
      )
    end

    unless Defaults.ad_dns_zone?
      _process_deploy_r53_dns_records(
        template: template
      )
    end

    template
  end

  def deploy_ad_dns_records
    # Create DNS name for this component
    dns_name = Defaults.deployment_dns_name(
      component: component_name,
      zone: Defaults.ad_dns_zone
    )

    endpoint = Context.component.variable(
      @component_name,
      "#{@stream_name}Arn"
    )
    Util::Nsupdate.create_dns_record(dns_name, endpoint, "TXT", 60)
    Log.debug("#{@component_name} ARN: #{endpoint}")
    Log.output("#{@component_name} DNS: #{dns_name}")

    @destination.each do |destination_name, definition|
      # Create DNS name for this component
      dns_name = Defaults.deployment_dns_name(
        component: @component_name,
        resource: destination_name,
        zone: Defaults.ad_dns_zone
      )

      endpoint = Context.component.variable(@component_name, "#{destination_name}Arn")

      Util::Nsupdate.create_dns_record(dns_name, endpoint, "TXT", 60)
      Log.debug("#{@component_name} ARN: #{endpoint}")
      Log.output("#{@component_name} DNS: #{dns_name}")
    end
  end

  def _process_deploy_r53_dns_records(template: nil)
    dns_name = Defaults.deployment_dns_name(
      component: component_name,
      zone: Defaults.dns_zone
    )
    Log.output("#{@component_name} DNS: #{dns_name}")
    stream_name = @stream.keys.first
    _process_route53_records(
      template: template,
      record_sets: {
        "#{@component_name}DeployDns".gsub(/[^a-zA-Z0-9]/, '') => {
          "Properties" => {
            "Name" => dns_name,
            "Type" => "TXT",
            "TTL" => "60",
            "ResourceRecords" => [
              JsonTools.hash_to_cfn_join(
                'Fn::GetAtt' => [stream_name, 'Arn']
              )
            ]
          }
        }
      }
    )

    @destination.each do |name, definition|
      dns_name = Defaults.deployment_dns_name(
        component: component_name,
        resource: name,
        zone: Defaults.dns_zone
      )
      Log.output("#{@component_name} DNS: #{dns_name}")
      _process_route53_records(
        template: template,
        record_sets: {
          "#{@component_name}#{name}DeployDns".gsub(/[^a-zA-Z0-9]/, '') => {
            'Properties' => {
              'Name' => dns_name,
              'Type' => 'TXT',
              'TTL' => '60',
              'ResourceRecords' => [
                JsonTools.hash_to_cfn_join('Fn::GetAtt' => [name, 'Arn'])
              ]
            }
          }
        }
      )
    end
  end

  # Clean up deployment DNS record in AD DNS zone
  def _clean_ad_deployment_dns_record(component_name)
    # Skip clean up of records unless AD dns zone is used or global teardown
    return unless Defaults.ad_dns_zone? || Context.environment.variable('custom_buildNumber', nil)

    dns_name = Defaults.deployment_dns_name(
      component: component_name,
      zone: Defaults.ad_dns_zone
    )

    Util::Nsupdate.delete_dns_record(dns_name) unless dns_name.nil?

    @destination.each do |destination_name, definition|
      # Create DNS name for this component
      dns_name = Defaults.deployment_dns_name(
        component: @component_name,
        resource: destination_name,
        zone: Defaults.ad_dns_zone
      )

      Util::Nsupdate.delete_dns_record(dns_name) unless dns_name.nil?
    end
  rescue => error
    Log.error "Failed to delete deployment DNS record #{dns_name} - #{error}"
    raise "Failed to delete deployment DNS record #{dns_name} - #{error}"
  end

  # Clean up release DNS record if required
  def _clean_ad_release_dns_record(component_name)
    return unless Context.persist.released_build? || Context.persist.released_build_number.nil?

    dns_name = Defaults.release_dns_name(
      component: component_name,
      zone: Defaults.ad_dns_zone
    )
    Util::Nsupdate.delete_dns_record(dns_name) unless dns_name.nil?
    @destination.each do |destination_name, definition|
      # Create DNS name for this component
      dns_name = Defaults.deployment_dns_name(
        component: @component_name,
        resource: destination_name,
        zone: Defaults.ad_dns_zone
      )

      Util::Nsupdate.delete_dns_record(dns_name) unless dns_name.nil?
    end
  rescue => error
    Log.error "Failed to delete release DNS record #{dns_name} - #{error}"
    raise "Failed to delete release DNS record #{dns_name} - #{error}"
  end
end
