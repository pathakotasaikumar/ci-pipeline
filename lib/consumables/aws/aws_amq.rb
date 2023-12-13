require 'consumable'
require_relative 'builders/amq_broker_builder'
require_relative 'builders/amq_configuration_builder'
require_relative 'builders/dns_record_builder'
require_relative 'builders/route53_record_builder'

# Extends Consumable class
# Builds aws/amq pipeline component
class AwsAmq < Consumable
  include AmqBrokerBuilder
  include AmqConfigurationBuilder
  include Route53RecordBuilder
  include DnsRecordBuilder

  # @param (see Consumable#initialize)
  def initialize(component_name, definition)
    super(component_name, definition)

    @amq_broker = {}
    @amq_configuration = {}
    @template_parameters = {}

    # Load resources from the component definition
    (definition["Configuration"] || {}).each do |name, resource|
      raise "Invalid resource name #{name.inspect}" unless name =~ /^[a-zA-Z][a-zA-Z0-9]*$/

      type = resource["Type"]

      case type
      when "AWS::AmazonMQ::Broker"
        raise "This component does not support multiple #{type} resources" unless @amq_broker.empty?

        @amq_broker[name] = resource
      when "AWS::AmazonMQ::Configuration"
        raise "This component does not support multiple #{type} resources" unless @amq_configuration.empty?

        @amq_configuration[name] = resource
      when nil
        raise "Must specify a type for resource #{name.inspect}"
      else
        raise "Resource type #{type.inspect} is not supported by this component"
      end
    end
    @amq_broker_name = @amq_broker.keys.first
    @amq_configuration_name = @amq_configuration.keys.first
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
    mappings["create"] = %w(
      mq:CreateUser
    )

    mappings["admin"] = mappings["create"] + %w(
      mq:DeleteUser
    )

    definition = @amq_broker.values.first

    unless definition["Security"].nil? || definition["Security"].empty?
      security_rules += _parse_security_rules(
        type: :auto,
        rules: definition['Security'],
        mappings: mappings,
        destination_iam: "*", # Amazon MQ doesnt support resource level permission
        destination_ip: "#{@component_name}.SecurityGroup",
      )
    end

    return security_rules
  end

  # Deploys AMQ
  def deploy
    # Creates AMQ Configuration template

    template = _build_amq_configuration_template

    configuration_stack_name = _amq_configuration_stack_name

    params = {
      stack_name: configuration_stack_name,
      template: template,
      wait_delay: 10
    }

    # Create CFN Stack to create AMQ Configuration.
    # It is created at branch level

    stack_outputs = {}

    begin
      Log.debug "Creating AMQ Configuration stack - #{configuration_stack_name}"
      if AwsHelper.cfn_stack_exists(configuration_stack_name).nil?
        Log.info "AMQ Configuration for this branch doesnt exist - Creating new"
        tags = Defaults.get_tags(@component_name)
        params[:tags] = tags
        stack_outputs = AwsHelper.cfn_create_stack(**params)
      else
        stack_outputs = AwsHelper.cfn_update_stack(**params)
      end
    rescue => e
      stack_outputs = e.is_a?(ActionError) ? e.partial_outputs : {}
      raise "Failed to create stack - #{e}"
    ensure
      unless stack_outputs.nil? || stack_outputs.empty?
        Log.debug "Replacing - #{stack_outputs['StackId']}"
        stack_outputs['AMQConfigurationStackId'] = stack_outputs.delete 'StackId'
      end
      Context.component.set_variables(@component_name, stack_outputs)
    end

    # Tag AMQ Configuration created because tags are not propagated through CFN

    AwsHelper.apply_amq_tags(
      resource_arn: Context.component.variable(@component_name, "#{@amq_configuration_name}Arn", nil),
      tags: get_tags(component_name: @component_name)
    )

    # Check AMQ Password details

    _validate_amq_password

    # Get the stack name
    stack_name = Defaults.component_stack_name(@component_name)
    tags = Defaults.get_tags(@component_name)

    @template = _build_broker_template

    Context.component.set_variables(@component_name, { 'Template' => @template })

    _process_amq_template_parameters

    begin
      # Just check how the template looks like
      stack_outputs = {}
      stack_outputs = AwsHelper.cfn_create_stack(
        stack_name: stack_name,
        template: @template,
        tags: tags,
        template_parameters: @template_parameters
      )
    rescue => e
      stack_outputs = e.is_a?(ActionError) ? e.partial_outputs : {}
      raise "Failed to create stack - #{e}"
    ensure
      Context.component.set_variables(@component_name, stack_outputs)
    end

    # Tag AMQ Broker
    broker_tags = get_tags(
      component_name: @component_name,
      build_no: Defaults.sections[:build].upcase
    )

    AwsHelper.apply_amq_tags(
      resource_arn: Context.component.variable(@component_name, "#{@amq_broker_name}BrokerArn", nil),
      tags: broker_tags
    )

    # return unless Defaults.ad_dns_zone?
    begin
      if Defaults.ad_dns_zone?
        Log.debug 'Deploying AD DNS records'
        deploy_amq_ad_dns_records
      end
    rescue => error
      Log.error "Failed to deploy DNS records - #{error}"
      raise "Failed to deploy DNS records - #{error}"
    end
  end

  # Run release action for the component
  def release
    super
  end

  # Run teardown action for the component
  def teardown
    exception = nil

    # Delete AMQ component stack
    begin
      Log.debug "Deleting AMQ Broker stack"
      stack_id = Context.component.stack_id(@component_name)
      AwsHelper.cfn_delete_stack(stack_id) unless stack_id.nil?
    rescue => e
      exception ||= e
      Log.warn "Failed to delete stack #{stack_id.inspect} during teardown - #{e}"
    end

    begin
      _clean_amq_ad_deployment_dns_record
      _clean_amq_ad_release_dns_record if Context.persist.released_build? || Context.persist.released_build_number.nil?
    rescue => e
      exception ||= e
      Log.warn "Failed to remove AD DNS records during teardown - #{e}"
    end

    # Delete AMQ Configuration stack
    if Context.persist.released_build_number == Defaults.sections[:build] ||
       Context.persist.released_build_number.nil?
      begin
        stack_id = Context.component.variable(@component_name, 'AMQConfigurationStackId', nil)
        AwsHelper.cfn_delete_stack(stack_id) unless stack_id.nil?
      rescue => e
        exception ||= e
        Log.warn "Failed to delete stack #{stack_id.inspect} during teardown - #{e}"
      end
    end

    raise exception unless exception.nil?
  end

  # Creates Release DNS record for AMQ Broker
  # @param component_name [String] Name of the component
  def create_ad_release_dns_records(component_name:)
    dns_name = Defaults.release_dns_name(
      component: component_name,
      resource: "#{@amq_broker_name}-p",
      zone: Defaults.ad_dns_zone
    )

    endpoint = Context.component.variable(@component_name, "#{@amq_broker_name}PrimaryDeployDnsName")
    Util::Nsupdate.create_dns_record(dns_name, endpoint, "CNAME", 60)
    Log.output("#{@component_name} #{@amq_broker_name}-p DNS: #{dns_name}")

    unless JsonTools.get(@amq_broker.values.first, "Properties.DeploymentMode", "SINGLE_INSTANCE") == "SINGLE_INSTANCE"
      dns_name = Defaults.release_dns_name(
        component: component_name,
        resource: "#{@amq_broker_name}-s",
        zone: Defaults.ad_dns_zone
      )

      endpoint = Context.component.variable(@component_name, "#{@amq_broker_name}SecondaryDeployDnsName")
      Util::Nsupdate.create_dns_record(dns_name, endpoint, "CNAME", 60)
      Log.output("#{@component_name}  #{@amq_broker_name}-s DNS: #{dns_name}")
    end
  end

  # Creates primary and secondary name record
  def name_records
    records = {}
    # Generate Name record based on the Deployment Type

    records["#{@amq_broker_name}PrimaryDeployDnsName"] = Defaults.deployment_dns_name(
      component: component_name,
      resource: "#{@amq_broker_name}-p",
      zone: Defaults.dns_zone
    )
    records["#{@amq_broker_name}PrimaryReleaseDnsName"] = Defaults.release_dns_name(
      component: component_name,
      resource: "#{@amq_broker_name}-p",
      zone: Defaults.dns_zone
    )

    unless JsonTools.get(@amq_broker.values.first, "Properties.DeploymentMode", "SINGLE_INSTANCE") == "SINGLE_INSTANCE"
      # Deploying Single Instance

      records["#{@amq_broker_name}SecondaryDeployDnsName"] = Defaults.deployment_dns_name(
        component: component_name,
        resource: "#{@amq_broker_name}-s",
        zone: Defaults.dns_zone
      )
      records["#{@amq_broker_name}SecondaryReleaseDnsName"] = Defaults.release_dns_name(
        component: component_name,
        resource: "#{@amq_broker_name}-s",
        zone: Defaults.dns_zone
      )
    end

    raise "Unable to create DNS Record" if records.nil? || records.empty?

    return records
  end

  # Creates Deployed DNS record
  def deploy_amq_ad_dns_records
    # Create DNS record for AMQ

    dns_name = Defaults.deployment_dns_name(
      component: component_name,
      resource: "#{@amq_broker_name}-p",
      zone: Defaults.ad_dns_zone
    )

    endpoint = Context.component.variable(@component_name, "#{@amq_broker_name}PrimaryBrokerEndpoint")
    Util::Nsupdate.create_dns_record(dns_name, endpoint, "CNAME", 60)
    Log.output("#{@component_name} #{@amq_broker_name}-p DNS: #{dns_name}")

    unless JsonTools.get(@amq_broker.values.first, "Properties.DeploymentMode", "SINGLE_INSTANCE") == "SINGLE_INSTANCE"
      dns_name = Defaults.deployment_dns_name(
        component: component_name,
        resource: "#{@amq_broker_name}-s",
        zone: Defaults.ad_dns_zone
      )

      endpoint = Context.component.variable(@component_name, "#{@amq_broker_name}SecondaryBrokerEndpoint")
      Util::Nsupdate.create_dns_record(dns_name, endpoint, "CNAME", 60)
      Log.output("#{@component_name}  #{@amq_broker_name}-s DNS: #{dns_name}")
    end
  end

  # Get the list of tags for the resource
  # @param component_name [String] name of the component
  # @param build_no [Integer] Current build number. This is required while tagging Amazon MQ Broker
  # @return tags [Hash] the tags to be applied on AMQ Broker and Configuration
  def get_tags(component_name:, build_no: nil)
    sections = Defaults.sections
    tags = {
      'AMSID' => sections[:ams].upcase,
      'EnterpriseAppID' => sections[:qda].upcase,
      'ApplicationServiceID' => sections[:as].upcase,
      'Environment' => sections[:ase].upcase,
      'AsbpType' => sections[:asbp_type].upcase,
      'Name' => Defaults.build_specific_id(component_name).join("-")

    }
    if build_no.nil?
      tags[:Name] = Defaults.env_specific_id(component_name).join("-")
    else
      tags[:Name] = Defaults.build_specific_id(component_name).join("-")
      tags[:Build] = build_no
      tags[:Branch] = sections[:branch].upcase
    end
    return tags
  end

  private

  # Generates AMQ Configuration stack name
  def _amq_configuration_stack_name
    sections = Defaults.sections
    [
      sections[:ams],
      sections[:qda],
      sections[:as],
      sections[:ase],
      sections[:branch],
      @component_name
    ].join('-').gsub(/[^a-zA-Z0-9\-]/, '-')
  end

  # Creates AMQ Configuration template.
  # This is a temp solution once AWS allows to delete AMQ Configuration this can be deleted.
  # @return template [Hash] Cloudformation template required to create Amazon MQ Configuration
  def _build_amq_configuration_template
    template = { "Resources" => {}, "Outputs" => {} }

    _process_amq_configuration_builder(
      template: template,
      component_name: @component_name,
      amq_configuration: @amq_configuration
    )
    template
  end

  # Builds out AWS::AmazonMQ::Broker CloudFormation template
  # @return [Hash] CloudFormation template representation
  def _build_broker_template
    # Get security group ids

    template = { "Resources" => {}, "Outputs" => {} }
    security_group_ids = [Context.component.sg_id(@component_name, "SecurityGroup")]
    security_group_ids << Context.asir.destination_sg_id if ingress?

    amq_configuration = {
      amq_configuration_id: Context.component.variable(@component_name, "#{@amq_configuration_name}Id"),
      amq_configuration_revision: Context.component.variable(@component_name, "#{@amq_configuration_name}Revision")
    }

    # Create AMQ Broker
    # Pass the value of AMQ Configuration ID and Revision
    _process_amq_broker_builder(
      template: template,
      component_name: @component_name,
      amq_broker: @amq_broker,
      security_groups: security_group_ids,
      amq_configuration: amq_configuration,
      subnet_ids: _subnet_ids(
        deployment_mode: JsonTools.get(@amq_broker.values.first, "Properties.DeploymentMode"),
        subnet_alias: JsonTools.get(@amq_broker.values.first, "Properties.SubnetIds", '@private')
      )
    )

    template
  end

  # Validate if the password provided in component definition starts with @app
  def _validate_amq_password
    amq_user_password = JsonTools.get(@amq_broker.values.first, "Properties.Users", nil)

    amq_user_password.each do |user|
      unless user['Password'].nil?
        unless user['Password'] =~ /^@app.([0-9a-zA-Z_\/]+)$/
          raise ArgumentError, "AMQ Master Password can't be set as plaintext value."\
          "Use the QCP Secret Manager to encrypt the password and reference it in your YAML."
        end
      end
      _process_amq_admin_password(user_definition: user)
    end
  end

  # Updates template variable
  def _process_amq_template_parameters
    return unless @template.key? 'Parameters'

    template_param = @template['Parameters']

    template_param.keys.each do |name|
      next unless name.is_a? String
      next unless name.downcase.include?('username') || name.downcase.include?('password')

      param_value = Context.component.variable(@component_name, name, '')

      if param_value == :undef || param_value.nil? || param_value.empty?
        raise "Context variable [#{name}] is undefined, nil or empty"
      end

      @template_parameters[name] = param_value
    end
  end

  # Deletes deployed DNS record
  def _clean_amq_ad_deployment_dns_record
    # Skip clean up of records unless AD dns zone is used or global teardown
    return unless Defaults.ad_dns_zone? || Context.environment.variable('custom_buildNumber', nil)

    begin
      dns_name = Defaults.deployment_dns_name(
        component: component_name,
        resource: "#{@amq_broker_name}-p",
        zone: Defaults.ad_dns_zone
      )

      Util::Nsupdate.delete_dns_record(dns_name) unless dns_name.nil?
    rescue => e
      Log.error "Failed to delete DNS record #{dns_name} during teardown - #{e}"
      raise "Failed to delete DNS record #{dns_name} during teardown - #{e}"
    end

    unless JsonTools.get(@amq_broker.values.first, "Properties.DeploymentMode", "SINGLE_INSTANCE") == "SINGLE_INSTANCE"
      begin
        dns_name = Defaults.deployment_dns_name(
          component: component_name,
          resource: "#{@amq_broker_name}-s",
          zone: Defaults.ad_dns_zone
        )

        Util::Nsupdate.delete_dns_record(dns_name) unless dns_name.nil?
      rescue => e
        Log.error "Failed to delete DNS record #{dns_name} during teardown - #{e}"
        raise "Failed to delete DNS record #{dns_name} during teardown - #{e}"
      end
    end
  end

  # Delete released ad dns record
  def _clean_amq_ad_release_dns_record
    # Delete AMQ Release DNS record

    begin
      dns_name = Defaults.release_dns_name(
        component: component_name,
        resource: "#{@amq_broker_name}-p",
        zone: Defaults.ad_dns_zone
      )

      Util::Nsupdate.delete_dns_record(dns_name) unless dns_name.nil?
    rescue => e
      Log.error "Failed to delete DNS record #{dns_name} during teardown - #{e}"
      raise "Failed to delete DNS record #{dns_name} during teardown - #{e}"
    end

    unless JsonTools.get(@amq_broker.values.first, "Properties.DeploymentMode", "SINGLE_INSTANCE") == "SINGLE_INSTANCE"
      begin
        dns_name = Defaults.release_dns_name(
          component: component_name,
          resource: "#{@amq_broker_name}-s",
          zone: Defaults.ad_dns_zone
        )

        Util::Nsupdate.delete_dns_record(dns_name) unless dns_name.nil?
      rescue => e
        Log.error "Failed to delete DNS record #{dns_name} during teardown - #{e}"
        raise "Failed to delete DNS record #{dns_name} during teardown - #{e}"
      end
    end
  end
end
