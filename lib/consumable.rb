require 'action'
require 'defaults'
require 'pipeline/feature'
require 'util/json_tools'
require_relative 'consumables/aws/builders/security_item_builder'
require_relative 'consumables/aws/builders/security_rule_builder'

# Base class for pipeline Consumables
# @attr_reader component_name [String] name of the component (from component definition file)
# @attr_reader stage [String] deployment stage the component
# @attr_reader definition [Hash] definition as read from component definition file
# @attr_reader persist [String, Boolean] persist flag for component
# @attr_reader actions [Hash] action definitions as read from component definition file

class Consumable
  include SecurityItemBuilder
  include SecurityRuleBuilder

  attr_reader :component_name
  attr_reader :stage
  attr_reader :definition
  attr_reader :persist
  attr_reader :actions
  attr_reader :type
  attr_reader :pipeline_features

  @@consumables = nil
  @@consumable_definitions = nil

  # @param component_name [String] name of the component as specified with yaml file name
  # @param definition [Hash] component definition as specified in YAML file
  def initialize(component_name, definition)
    # Validate the component name
    raise ArgumentError, "Component name cannot be 'pipeline' - this is a reserved name" if component_name.downcase == "pipeline"
    raise ArgumentError, "Component name cannot start with _ - this is a reserved" if component_name.start_with? '_'
    raise ArgumentError, "The component name contains illegal characters, legal characters are [a-zA-Z0-9\\-_]" if component_name !~ /^[a-zA-Z0-9\-_]+$/
    raise ArgumentError, "A stage must be specified for every component" unless definition.has_key? 'Stage'
    raise ArgumentError, "Expecting a string for the Stage parameter, but is a #{definition['Stage'].class.inspect}" unless definition['Stage'].is_a? String

    @component_name = component_name
    @stage = definition['Stage']
    @type = definition['Type']
    @definition = definition
    @persist = Context.environment.persist_override(component_name, definition['Persist'])
    @pipeline_features = load_features
    @features = {}
    @actions = []
    actions_definitions = definition["Actions"] || []
    load_actions(actions_definitions) unless actions_definitions.empty?
  end

  # Override in subclass
  # @return [Array] Security Items - SecurityGroups and IAM roles applicable to the component
  def security_items
    raise "Must override method 'security_items' in consumable sub class"
  end

  # Override in subclass
  # @return [Array] Security Items - IP security rules and IAM policies applicable to the component
  def security_rules
    raise "Must override method 'security_rules' in consumable sub class"
  end

  # Runs deployment stage before "deploy/finalise_security_rules calls
  def pre_deploy
  end

  # Runs deployment stage after "deploy/finalise_security_rules calls
  # This is used mostly by CodeDeploy component to stay within one stack / component definition
  def post_deploy
  end

  # Runs deployment stage before component 'release' calls
  def pre_release
  end

  # Runs deployment stage after component 'release' calls
  def post_release
  end

  # Runs deployment stage before component 'teardown' calls
  def pre_teardown
  end

  # Runs deployment stage after component 'teardown' calls
  def post_teardown
  end

  # flags is active build update should be performed
  # by default, true
  # codedeploy component uses it to avoid normal active build updates in codedeploy mode
  def update_active_build?
    true
  end

  # Runs deployment stage for specified component
  def deploy
    raise "Must override method 'deploy' in consumable sub class"
  end

  # Runs release stage for specified component
  def release
    # raise "Must override method 'release' in consumable sub class"
  end

  # Runs teardown stage for specified component
  def teardown
    raise "Must override method 'teardown' in consumable sub class"
  end

  # @return [Hash] Deploy and Release DNS records for the component
  def name_records
    {
      'DeployDnsName' => Defaults.deployment_dns_name(
        component: component_name,
        zone: Defaults.dns_zone
      ),
      'ReleaseDnsName' => Defaults.release_dns_name(
        component: component_name,
        zone: Defaults.dns_zone
      )
    }
  end

  # Deploy security stack for the component
  def deploy_security_items
    if !Context.component.stack_id(@component_name).nil?
      Log.info "Persisting component #{component_name.inspect} security items from build #{Context.component.build_number(@component_name)}"
    else
      Log.info "Deploying security items for component #{@component_name.inspect}"

      stack_name = Defaults.component_security_stack_name(@component_name)
      tags = Defaults.get_tags(@component_name)
      template = { 'Resources' => {}, 'Outputs' => {} }
      _process_security_items(
        template: template,
        vpc_id: Context.environment.vpc_id,
        security_items: security_items,
      )

      if template['Resources'].empty?
        # No rules - add dummy resource so stack doesn't fail
        template['Resources']['NoItems'] = {
          'Type' => 'AWS::CloudFormation::WaitConditionHandle',
          'Properties' => {}
        }
      end

      begin
        stack_outputs = {}
        stack_outputs = AwsHelper.cfn_create_stack(stack_name: stack_name, template: template, tags: tags)
      rescue => e
        stack_outputs = (e.is_a? ActionError) ? e.partial_outputs : {}
        raise "Failed to create security items stack for component #{@component_name} - #{e}"
      ensure
        sg_id_map = stack_outputs.select { |key, value| !key.start_with? 'Stack' }
        Context.component.set_security_details(@component_name, stack_outputs['StackId'], sg_id_map)
      end
    end
  end

  # Teardown security stack for teh component
  def teardown_security_items
    exception = nil

    # Delete security items stack
    begin
      stack_id = Context.component.security_stack_id(@component_name)
      unless stack_id.nil?
        Log.info "Deleting security stack with id #{stack_id.inspect}"
        AwsHelper.cfn_delete_stack(stack_id)
      end
    rescue => e
      exception ||= e
      Log.warn "Failed to delete component #{@component_name.inspect} security stack #{stack_id.inspect} during teardown - #{e}"
    end

    raise exception unless exception.nil?
  end

  # Update security rules for the component
  def finalise_security_rules
    _update_security_rules(
      rules: security_rules,
      skip_non_existant: false,
      create_empty: true,
    )
  end

  # Parse security rules from component definition and generate SecurityRule objects
  # @return [Array] list of IpSecurityRule and IamSecurityRule objects
  # @param rules [Array] list of rules from component definition
  # @param destination [String] generic destination for the rule
  # @param type [Symbol] rule type (:ip, :iam or :auto)
  # @param mappings [Hash] Key Value pairs for rule sets
  # @param destination_ip [String] destination for IP rule
  # @param destination_iam [String] destination for IAM rule
  # @return [Array] List of SecurityRules objects (see SecurityRule)
  def _parse_security_rules(
    rules: nil,
    destination: nil,
    type: :auto,
    mappings: {},
    destination_ip: nil,
    destination_iam: nil,
    condition_iam: nil
  )
    return [] if rules.nil?
    raise "Expecting an Array for security rules, but received a #{rules.class}" unless rules.is_a? Array

    security_rules = []
    rules.each do |rule|
      source = rule['Source']

      rule_type = type if [:ip, :iam].include?(type)

      # Add the rule to the list of rules
      if type == :auto
        if source.end_with? 'SecurityGroup'
          rule_type = :ip
          destination = destination_ip unless destination_ip.nil?
        elsif source.end_with? 'Role'
          rule_type = :iam
          destination = destination_iam unless destination_iam.nil?
        else
          raise "Could not determine security rule type from source #{source.inspect}"
        end
      else
        raise "Provided rule type #{type} does not match valid types: [:ip, :iam, :auto]" if ![:ip, :iam, :auto].include?(type)
      end

      if rule_type == :ip
        # Build the array of allow rules
        allow_rules = Array(rule['Allow']).map { |allow_rule|
          next mappings[allow_rule.downcase] if mappings.has_key? allow_rule.downcase

          next allow_rule
        }.flatten.uniq

        security_rules << IpSecurityRule.new(
          sources: source,
          destination: destination,
          ports: allow_rules,
        )
      elsif rule_type == :iam
        # Build the array of allow rules
        allow_rules = Array(rule['Allow']).map { |allow_rule|
          raise "Unknown security allow rule #{allow_rule.inspect}, expecting one of: #{mappings.keys.inspect}" unless mappings.has_key? allow_rule

          next mappings[allow_rule.downcase]
        }.flatten.uniq

        security_rules << IamSecurityRule.new(
          roles: source,
          resources: destination,
          actions: allow_rules,
          condition: condition_iam || rule['Condition']
        )
      end
    end

    return security_rules
  end

  # Update existing security rules stack
  # @param rules
  def _update_security_rules(
    rules: nil,
    skip_non_existant: true,
    create_empty: false
  )
    template = { 'Resources' => {} }

    _process_security_rules(
      template: template,
      component_name: @component_name,
      rules: rules,
      skip_non_existant: skip_non_existant,
    )

    stack_name = Defaults.security_rules_stack_name(@component_name)
    stack_id = AwsHelper.cfn_stack_exists(stack_name)

    if template['Resources'].empty?
      # Don't create a new stack if create_empty is false
      return if stack_id.nil? and create_empty == false

      # No rules - add dummy resource so stack doesn't fail
      template['Resources']['NoRules'] = {
        'Type' => 'AWS::CloudFormation::WaitConditionHandle',
        'Properties' => {},
      }
    end

    if stack_id.nil?
      # We don't have a security stack yet - build one
      Log.info "Deploying security rules for component #{@component_name.inspect}"
      tags = Defaults.get_tags(@component_name)

      stack_outputs = {}
      begin
        stack_outputs = AwsHelper.cfn_create_stack(
          stack_name: stack_name,
          template: template,
          tags: tags,
          wait_delay: 15
        )
      rescue => e
        stack_outputs = e.is_a?(ActionError) ? e.partial_outputs : {}
        raise "Failed to create security rules stack for component #{@component_name.inspect} - #{e}"
      end
    else
      # We already have a security stack - update it with the new template
      Log.info "Updating security rules for component #{@component_name.inspect}"
      begin
        AwsHelper.cfn_update_stack(stack_name: stack_id, template: template)
      rescue => e
        raise "Failed to update security rules stack for component #{@component_name.inspect} - #{e}"
      end
    end
  end

  # Teardown security rules stack for the component
  def teardown_security_rules
    stack_name = Defaults.security_rules_stack_name(@component_name)
    stack_id = AwsHelper.cfn_stack_exists(stack_name)
    unless stack_id.nil?
      Log.info "Deleting security rules stack #{stack_name}"
      AwsHelper.cfn_delete_stack(stack_id)
    end
  rescue => error
    Log.warn "Failed to delete component #{@component_name} security rules for stack #{stack_name} during teardown - #{error}"
  end

  # Parse Actions as specified in the component definition
  # Set @actions instance variable with parse results
  # @param definitions [Hash] Actions as specified in the component definition
  def load_actions(definitions)
    definitions.each do |stage, actions|
      actions.each do |action|
        begin
          @actions << Action.instantiate(
            name: action["Action"],
            component: self,
            params: (action["Parameters"] || {}),
            stage: stage,
            step: action["Stage"] || "00"
          )
        rescue => e
          Log.warn "Failed to initialise action #{action["Action"].inspect} for component #{@component_name} - #{e}"
          raise "Failed to initialise action #{action["Action"].inspect} - #{e}"
        end
      end
    end
  end

  # Iterate over the consumable definition and instantiate any available features
  # @return [List] List of Pipeline::Feature objects
  def load_features
    pipeline_features = []

    feature_definitions = default_pipeline_features
    (@definition["Configuration"] || {}).each do |resource_name, resource_definition|
      next unless resource_definition['Type'] == 'Pipeline::Features'

      # Merge default features with user specified
      feature_definitions.merge!(JsonTools.get(resource_definition, 'Properties.Features', {}))
    end

    # Instantiate Pipeline::Feature objects
    # Legacy Support: If feature is a simple toggle, normalise to a Hash with Enabled property
    feature_definitions.each do |feature_name, feature_definition|
      if feature_definition.is_a?(Hash)
        pipeline_features << Pipeline::Feature.instantiate(@component_name, feature_name, feature_definition)
      else
        feature_enabled = feature_definition.downcase == 'enabled' ? 'true' : 'false'
        pipeline_features << Pipeline::Feature.instantiate(@component_name, feature_name, { 'Enabled' => feature_enabled })
      end
    end

    return pipeline_features
  end

  # Create a new consumable object from the provided component definition
  # @param component_name [String] component name
  # @param definition [Hash] component definition
  def self.instantiate(component_name, definition)
    type = definition['Type']

    case type
    when "aws/alb"
      require 'consumables/aws/aws_alb'
      return AwsAlb.new(component_name, definition)
    when "aws/autoscale"
      require 'consumables/aws/aws_autoscale'
      return AwsAutoscale.new(component_name, definition)
    when "aws/autoheal"
      require 'consumables/aws/aws_autoheal'
      return AwsAutoheal.new(component_name, definition)
    when "aws/dummy"
      require 'consumables/aws/aws_dummy'
      return AwsDummy.new(component_name, definition)
    when "aws/dynamodb-table"
      require 'consumables/aws/aws_dynamodb_table'
      return AwsDynamoDbTable.new(component_name, definition)
    when "aws/ecs-task"
      require 'consumables/aws/aws_ecs_task'
      return AwsECSTask.new(component_name, definition)
    when "aws/elasticache-redis"
      require 'consumables/aws/aws_elasticache_redis'
      return AwsElastiCacheRedis.new(component_name, definition)
    when "aws/emr-cluster"
      require 'consumables/aws/aws_emr_cluster'
      return AwsEmrCluster.new(component_name, definition)
    when "aws/network-interface"
      require 'consumables/aws/aws_network_interface'
      return AwsNetworkInterface.new(component_name, definition)
    when "aws/image"
      require 'consumables/aws/aws_image'
      return AwsImage.new(component_name, definition)
    when "aws/instance"
      require 'consumables/aws/aws_instance'
      return AwsInstance.new(component_name, definition)
    when "aws/kinesis-stream"
      require 'consumables/aws/aws_kinesis'
      return AwsKinesis.new(component_name, definition)
    when "aws/kms"
      require 'consumables/aws/aws_kms'
      return AwsKms.new(component_name, definition)
    when "aws/lambda"
      require 'consumables/aws/aws_lambda'
      return AwsLambda.new(component_name, definition)
    when "aws/lambda-layer"
      require 'consumables/aws/aws_lambda_layer'
      return AwsLambdaLayer.new(component_name, definition)
    when "aws/efs"
      require 'consumables/aws/aws_efs'
      return AwsEfs.new(component_name, definition)
    when "aws/rds-mysql"
      require 'consumables/aws/aws_rds_mysql'
      return AwsRdsMysql.new(component_name, definition)
    when "aws/rds-postgresql"
      require 'consumables/aws/aws_rds_postgresql'
      return AwsRdsPostgresql.new(component_name, definition)
    when "aws/rds-sqlserver"
      require 'consumables/aws/aws_rds_sqlserver'
      return AwsRdsSqlserver.new(component_name, definition)
    when "aws/rds-oracle"
      require 'consumables/aws/aws_rds_oracle'
      return AwsRdsOracle.new(component_name, definition)
    when "aws/rds-aurora"
      require 'consumables/aws/aws_rds_aurora'
      return AwsRdsAurora.new(component_name, definition)
    when "aws/rds-aurora-postgresql"
      require 'consumables/aws/aws_rds_aurora_postgre'
      return AwsRdsAuroraPostgre.new(component_name, definition)
    when "aws/route53"
      require 'consumables/aws/aws_route53'
      return AwsRoute53.new(component_name, definition)
    when "aws/state-machine"
      require 'consumables/aws/aws_state_machine'
      return AwsStateMachine.new(component_name, definition)
    when "aws/sns-topic"
      require 'consumables/aws/aws_sns_topic'
      return AwsSnsTopic.new(component_name, definition)
    when "aws/sns-factory"
      require 'consumables/aws/aws_sns_factory'
      return AwsSnsFactory.new(component_name, definition)
    when "aws/sqs"
      require 'consumables/aws/aws_sqs'
      return AwsSqs.new(component_name, definition)
    when "aws/volume"
      require 'consumables/aws/aws_volume'
      return AwsVolume.new(component_name, definition)
    when "aws/vpc-endpoint-service"
      require 'consumables/aws/aws_vpc_endpoint_service'
      return AwsVPCEndpointService.new(component_name, definition)
    when "aws/s3-prefix"
      require 'consumables/aws/aws_s3_prefix'
      return AwsS3prefix.new(component_name, definition)
    when "aws/codedeploy"
      require 'consumables/aws/aws_codedeploy'
      return AwsCodeDeploy.new(component_name, definition)
    when "aws/amq"
      require 'consumables/aws/aws_amq'
      return AwsAmq.new(component_name, definition)
    else
      raise "Unknown consumable type #{type.inspect}"
    end
  end

  # Create consumable objects from all provided component definitions
  # @param component_definitions [Hash] component definition
  # @return [Hash] key value pairing of component names and definitions
  def self.instantiate_all(component_definitions)
    consumables = {}
    consumable_definitions = {}

    component_definitions.each do |component_name, component_definition|
      consumable_definitions[component_name] = component_definition

      consumable = Consumable.instantiate(component_name, component_definition)
      consumables[component_name] = consumable
    end

    @@consumables = consumables
    @@consumable_definitions = consumable_definitions

    return consumables
  end

  # Generate default feature tags for component
  # @return [Array] single key value pair
  def default_pipeline_features
    sections = Defaults.sections
    case sections[:env].downcase
    when 'nonp'
      { "Datadog" => "disabled" }
    when 'prod'
      { "Datadog" => "disabled" }
    else
      raise "Unknown environment"
    end
  end

  # Clean up deployment DNS record in AD DNS zone
  def _clean_ad_deployment_dns_record
    # Skip clean up of records unless AD dns zone is used or global teardown
    return unless Defaults.ad_dns_zone? || Context.environment.variable('custom_buildNumber', nil)

    dns_name = Defaults.deployment_dns_name(
      component: @component_name,
      zone: Defaults.ad_dns_zone
    )
    Util::Nsupdate.delete_dns_record(dns_name) unless dns_name.nil?
  rescue => error
    Log.error "Failed to delete deployment DNS record #{dns_name} - #{error}"
    raise "Failed to delete deployment DNS record #{dns_name} - #{error}"
  end

  # Clean up release DNS record if required
  def _clean_ad_release_dns_record
    return unless Context.persist.released_build? || Context.persist.released_build_number.nil?

    dns_name = Defaults.release_dns_name(
      component: @component_name,
      zone: Defaults.ad_dns_zone
    )
    Log.info dns_name.inspect
    Util::Nsupdate.delete_dns_record(dns_name) unless dns_name.nil?
  rescue => error
    Log.error "Failed to delete release DNS record #{dns_name} - #{error}"
    raise "Failed to delete release DNS record #{dns_name} - #{error}"
  end

  def ingress?
    @definition["IngressPoint"].to_s == 'true'
  end

  def self.get_consumables
    @@consumables
  end

  def self.get_consumable_definitions
    @@consumable_definitions || {}
  end
end
