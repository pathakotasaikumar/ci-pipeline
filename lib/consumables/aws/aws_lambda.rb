require_relative '../../consumable'
require_relative '../../util/archive'
require_relative 'builders/lambda_function_builder'
require_relative 'builders/lambda_permission_builder'
require_relative 'builders/events_rule_builder'
require_relative 'builders/security_rule_builder'
require_relative 'builders/sns_topic_builder'
require_relative "builders/logs_subscriptionfilter_builder"

# Extends Consumable class, builds aws/lambda pipeline component
class AwsLambda < Consumable
  include LambdaFunctionBuilder
  include LambdaPermissionBuilder
  include EventsRuleBuilder
  include SecurityRuleBuilder
  include SnsTopicBuilder
  include Util::Archive
  include LogsSubscriptionFilterBuilder

  # @param (see Consumable#initialize)
  def initialize(component_name, definition)
    super(component_name, definition)

    @lambda_function = {}
    @events_rule = {}
    @event_source_mapping = {}
    @sns_subscription = {}
    @logs_subscription_filter = {}

    # Load resources from the component definition
    (definition['Configuration'] || {}).each do |name, resource|
      type = resource['Type']

      case type
      when 'AWS::Lambda::Function'
        raise 'Multiple AWS::Lambda::Function resources found' if @lambda_function.any?

        @lambda_function[name] = resource
      when 'AWS::Events::Rule'
        @events_rule[name] = resource
      when 'AWS::Lambda::EventSourceMapping'
        @event_source_mapping[name] = resource
      when 'AWS::SNS::Subscription'
        @sns_subscription[name] = resource
      when 'AWS::Logs::SubscriptionFilter'
        @logs_subscription_filter[name] = resource
      when 'Pipeline::Features'
        @features[name] = resource
      else
        raise "Resource type #{type.inspect} is not supported by this component"
      end
    end

    @lambda_function_name = 'Function'

    @lambda_package_artefact = JsonTools.get(
      @lambda_function.values.first, 'Properties.Code', nil
    )

    # Test if the 'Code' property looks like a packaged artefact
    unless %w(.zip .jar).include?(File.extname(@lambda_package_artefact.to_s))
      raise "Lambda 'Code' property must be specified as a jar or zip file"
    end
  end

  # @return (see Consumable#security_items)
  def security_items
    [
      {
        "Name" => "SecurityGroup",
        "Type" => "SecurityGroup",
        "Component" => @component_name,
        "DeletionPolicy" => "Retain"
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

  # @return (see Consumable#security_rules)
  def security_rules
    security_rules = []

    mappings = {}
    mappings['execute'] = %w(
      lambda:Invoke*
    )

    # Attach base profile and security group rules
    security_rules += _base_security_rules(
      component_name: @component_name,
      role_name: 'ExecutionRole'
    )

    unless JsonTools.get(@lambda_function.values.first, "Properties.DeadLetterConfig", nil).nil?
      security_rules += _dead_letter_queue_permission(
        component_name: @component_name,
        role_name: 'ExecutionRole',
        definition: @lambda_function.values.first
      )
    end

    resource_arns = [
      Context.component.variable(@component_name, "#{@lambda_function_name}Arn", nil),
      _deploy_alias_arn,
      _release_alias_arn
    ].compact

    # Process access rules for other components
    security_rules += _parse_security_rules(
      type: :auto,
      mappings: mappings,
      rules: @lambda_function.values.first["Security"],
      destination_ip: "#{@component_name}.SecurityGroup",
      destination_iam: resource_arns
    )

    return security_rules
  end

  def deploy
    # Unpack and upload specified lambda artefact package
    _upload_package_artefact(@lambda_package_artefact)

    # Create security groups
    _update_security_rules(rules: security_rules)

    function_stack_name = _lambda_function_stack_name
    template = _function_template

    params = {
      stack_name: function_stack_name,
      template: template,
      wait_delay: 10
    }

    stack_outputs = {}
    begin
      Log.info "Creating function stack - #{function_stack_name}"
      if AwsHelper.cfn_stack_exists(function_stack_name).nil?
        tags = Defaults.get_tags(@component_name)
        @pipeline_features.map { |f| tags += f.feature_tags }
        params[:tags] = tags
        stack_outputs = AwsHelper.cfn_create_stack(**params)
      else
        Log.info "Updating function stack - #{function_stack_name}"
        params[:max_attempts] = 30
        stack_outputs = AwsHelper.cfn_update_stack(**params)
      end
    rescue ActionError => e
      stack_outputs = e.partial_outputs
      raise "Failed to create lambda function stack - #{stack_outputs.inspect}- #{e}"
    ensure
      # Replace StackId output value with FunctionStackId
      unless stack_outputs.nil? || stack_outputs.empty?
        Log.debug "Replacing - #{stack_outputs['StackId']}"
        stack_outputs['FunctionStackId'] = stack_outputs.delete 'StackId'
      end
      Context.component.set_variables(@component_name, stack_outputs)
    end

    # Set Release and Deploy ARN variables as soon as we have the function name
    Context.component.set_variables(
      @component_name,
      'ReleaseArn' => _release_alias_arn,
      'DeployArn' => _deploy_alias_arn
    )

    # Create lambda version stack
    stack_outputs = {}
    begin
      function_name = Context.component.variable(@component_name, "#{@lambda_function_name}Name")
      tags = Defaults.get_tags(@component_name)
      @pipeline_features.map { |f| tags += f.feature_tags }
      stack_outputs = AwsHelper.cfn_create_stack(
        stack_name: Defaults.component_stack_name(@component_name),
        template: _version_template(function_name),
        wait_delay: 10,
        tags: tags
      )
      Log.output "#{@component_name} version ARN: #{_deploy_alias_arn}"
    rescue ActionError => e
      stack_outputs = e.partial_outputs
      raise "Failed to create or update lambda version stack - #{e}"
    ensure
      Context.component.set_variables(@component_name, stack_outputs)
    end
  end

  def release
    release_stack_name = _lambda_release_stack_name
    function_name = Context.component.variable(@component_name, "#{@lambda_function_name}Name")
    function_version = Context.component.variable(@component_name, "#{@lambda_function_name}Version")

    params = {
      stack_name: release_stack_name,
      template: _release_template(function_name, function_version),
      wait_delay: 10
    }

    begin
      Log.info "Creating new Lambda release alias stack - #{release_stack_name}"
      stack_outputs = {}
      if AwsHelper.cfn_stack_exists(release_stack_name).nil?
        tags = Defaults.get_tags(@component_name)
        @pipeline_features.map { |f| tags += f.feature_tags }
        params[:tags] = tags
        stack_outputs = AwsHelper.cfn_create_stack(**params)
      else
        Log.info "Updating release stack - #{release_stack_name}"
        params[:max_attempts] = 30
        stack_outputs = AwsHelper.cfn_update_stack(**params)
      end
      Log.debug "#{@component_name} version target: #{function_version}"
      Log.output "#{@component_name} release ARN: #{_release_alias_arn}"
    rescue ActionError => e
      stack_outputs = e.partial_outputs
      raise "Failed to create or update release alias stack #{release_stack_name} - #{e}"
    ensure
      # Replace StackId output value with FunctionStackId
      unless stack_outputs.nil? || stack_outputs.empty?
        stack_outputs['ReleaseStackId'] = stack_outputs.delete 'StackId'
      end
      Context.component.set_variables(@component_name, stack_outputs)
    end
  end

  def teardown
    exception = nil

    if Context.persist.released_build_number == Defaults.sections[:build] ||
       Context.persist.released_build_number.nil?
      # Delete release alias stack
      begin
        stack_id = Context.component.variable(@component_name, 'ReleaseStackId', nil)
        AwsHelper.cfn_delete_stack(stack_id) unless stack_id.nil?
      rescue => e
        exception ||= e
        Log.warn "Failed to delete stack #{stack_id.inspect} during teardown - #{e}"
      end
    end

    # Delete version stack
    begin
      stack_id = Context.component.stack_id(@component_name)
      AwsHelper.cfn_delete_stack(stack_id) unless stack_id.nil?
    rescue => e
      exception ||= e
      Log.warn "Failed to delete stack #{stack_id.inspect} during teardown - #{e}"
    end

    versions = {}
    begin
      # Delete the 'Latest' function stack if this is the last version
      function_name = Context.component.variable(@component_name, "#{@lambda_function_name}Name", nil)
      versions = AwsHelper.lambda_versions(function_name: function_name) unless function_name.nil?
    rescue => e
      exception ||= e
      Log.warn "Unable to query versions for for #{@lambda_function_name}"
    end

    version_count = (versions.nil? || versions.empty?) ? nil : versions.size

    # Delete function stack if this is the last version or there are no active version
    if (version_count == 1 && versions.first.version == "$LATEST") || version_count.nil?
      begin
        stack_id = Context.component.variable(@component_name, 'FunctionStackId', nil)
        AwsHelper.cfn_delete_stack(stack_id) unless stack_id.nil?
      rescue => e
        exception ||= e
        Log.warn "Failed to delete stack #{stack_id.inspect} during teardown - #{e}"
      end
    end

    raise exception unless exception.nil?
  end

  # @return [Hash] Deploy and Release ARNs for the component
  def name_records
    {}
  end

  private

  # @return [String] Constructed ARN for release alias
  def _release_alias_arn
    real_function_name = Context.component.variable(@component_name, "#{@lambda_function_name}Name", nil)
    return nil if real_function_name.nil?

    [
      "arn:aws:lambda",
      Context.environment.region,
      Context.environment.account_id,
      "function",
      real_function_name,
      "release"
    ].join(':')
  end

  # @return [String] Constructed ARN for deploy alias
  def _deploy_alias_arn
    real_function_name = Context.component.variable(@component_name, "#{@lambda_function_name}Name", nil)
    return nil if real_function_name.nil?

    [
      "arn:aws:lambda",
      Context.environment.region,
      Context.environment.account_id,
      "function",
      real_function_name,
      "build-#{Defaults.sections[:build]}"
    ].join(':')
  end

  # Builds out AWS::Lambda::Function and other required resources
  # @return [Hash] CloudFormation template representation
  def _function_template
    template = { 'Resources' => { 'Function' => {} }, 'Outputs' => {} }

    _process_lambda_function(
      template: template,
      resource_name: 'Function',
      security_group_ids: [Context.component.sg_id(@component_name, "SecurityGroup"), Context.asir.source_sg_id],
      function_definition: @lambda_function,
      role: Context.component.role_arn(@component_name, "ExecutionRole")
    )

    _process_logs_subscription_filter(
      template: template,
      log_group: { 'Ref' => "#{@lambda_function_name}LogGroup" },
      definitions: @logs_subscription_filter
    )

    template
  end

  # Builds out AWS::Lambda::Version and AWS::Lambda::Permission resources
  # @param lambda_function [String] Reference to the lambda function
  # @return [Hash] CloudFormation template containing resources and outputs
  def _version_template(lambda_function)
    template = { "Resources" => {}, "Outputs" => {} }
    _process_lambda_version(
      template: template,
      lambda_function_name: @lambda_function_name,
      lambda_function: lambda_function
    )

    _process_lambda_alias(
      template: template,
      alias_definition: {
        'Deploy' => {
          'Type' => 'AWS::Lambda::Alias',
          'Properties' => {
            'FunctionName' => lambda_function,
            'FunctionVersion' => {
              'Fn::GetAtt' => ["#{@lambda_function_name}Version", 'Version']
            },
            'Name' => "build-#{Defaults.sections[:build]}"
          }
        }
      }
    )

    @events_rule.each do |name, definition|
      pipeline_event_target = JsonTools.get(definition, 'Properties.Pipeline::EventTarget', '@deployed')
      next unless pipeline_event_target == '@deployed'

      input = Context.component.replace_variables(
        JsonTools.get(definition, 'Properties.Pipeline::EventInput', {})
      )

      definition['Properties']['Targets'] = [{
        'Arn' => { 'Ref' => 'Deploy' },
        'Id' => @lambda_function_name,
        'Input' => input
      }]

      _process_events_rule(
        template: template,
        definitions: { name => definition }
      )

      _process_lambda_permission(
        template: template,
        permissions: {
          "#{name}ScheduledEventPermission" => {
            'Properties' => {
              'Action' => 'lambda:InvokeFunction',
              'FunctionName' => { 'Ref' => 'Deploy' },
              'Principal' => 'events.amazonaws.com',
              'SourceArn' => { 'Fn::GetAtt' => [name, 'Arn'] }
            }
          }
        }
      )
    end

    @event_source_mapping.each do |name, definition|
      pipeline_event_target = JsonTools.get(definition, 'Properties.Pipeline::EventTarget', '@deployed')
      next unless pipeline_event_target == '@deployed'

      Log.debug @event_source_mapping
      _process_event_source_mapping(
        template: template,
        function_name: { 'Ref' => 'Deploy' },
        definitions: Context.component.replace_variables(name => definition)
      )
    end

    @sns_subscription.each do |name, definition|
      pipeline_event_target = JsonTools.get(definition, 'Properties.Pipeline::EventTarget', '@deployed')
      next unless pipeline_event_target == '@deployed'

      topic_arn = Context.component.replace_variables(
        JsonTools.get(definition, 'Properties.TopicArn')
      )

      delivery_policy = JsonTools.get(definition, 'Properties.DeliveryPolicy', {})
      filter_policy = JsonTools.get(definition, 'Properties.FilterPolicy', {})

      _process_sns_subscription(
        template: template,
        definitions: {
          "#{name}SnsSubscription" => {
            'Type' => 'AWS::SNS::Subscription',
            'Properties' => {
              'Endpoint' => { 'Ref' => 'Deploy' },
              'Protocol' => 'lambda',
              'TopicArn' => topic_arn,
              'DeliveryPolicy' => delivery_policy,
              'FilterPolicy' => filter_policy
            }
          }
        }
      )

      _process_lambda_permission(
        template: template,
        permissions: {
          "#{name}SnsSubscriptionPermission" => {
            "Properties" => {
              'Action' => 'lambda:InvokeFunction',
              'FunctionName' => { 'Ref' => 'Deploy' },
              'Principal' => 'sns.amazonaws.com',
              'SourceArn' => topic_arn
            }
          }
        }
      )
    end

    _process_lambda_permission(
      template: template,
      permissions: _base_service_permissions(@lambda_function_name)
    )

    template
  end

  # Generates Lambda Release template, containing 'Release' alias
  # @param lambda_function_name [String] Name of the lambda function
  # @param lambda_version [FixNum] Version number
  # @return [Hash] CloudFromation template containing resources and outputs
  def _release_template(lambda_function_name, lambda_version)
    template = { "Resources" => {}, "Outputs" => {} }

    _process_lambda_alias(
      template: template,
      alias_definition: {
        "Release" => {
          "Type" => "AWS::Lambda::Alias",
          "Properties" => {
            "FunctionName" => lambda_function_name,
            "FunctionVersion" => lambda_version
          }
        }
      }
    )

    _process_lambda_permission(
      template: template,
      permissions: {
        'S3ASBucketPermissionForDeployAlias' => {
          'Type' => 'AWS::Lambda::Permission',
          'Properties' => {
            'Action' => 'lambda:InvokeFunction',
            'FunctionName' => { 'Ref' => 'Release' },
            'Principal' => 's3.amazonaws.com',
            'SourceArn' => Context.s3.as_bucket_arn
          }
        }
      }
    )

    @events_rule.each do |name, definition|
      pipeline_event_target = JsonTools.get(
        definition, 'Properties.Pipeline::EventTarget', '@deployed'
      )
      next unless pipeline_event_target == '@released'

      input = Context.component.replace_variables(
        JsonTools.get(definition, 'Properties.Pipeline::EventInput', '{}')
      )

      definition['Properties']['Targets'] = [{
        'Arn' => { 'Ref' => 'Release' },
        'Id' => @lambda_function_name,
        'Input' => input
      }]

      _process_events_rule(
        template: template,
        definitions: { name => definition }
      )

      _process_lambda_permission(
        template: template,
        permissions: {
          "#{name}ScheduledEventPermission" => {
            'Properties' => {
              'Action' => 'lambda:InvokeFunction',
              'FunctionName' => { 'Ref' => 'Release' },
              'Principal' => 'events.amazonaws.com',
              'SourceArn' => { 'Fn::GetAtt' => [name, 'Arn'] }
            }
          }
        }
      )
    end

    @event_source_mapping.each do |name, definition|
      pipeline_event_target = JsonTools.get(
        definition, 'Properties.Pipeline::EventTarget', '@deployed'
      )
      next unless pipeline_event_target == '@released'

      _process_event_source_mapping(
        template: template,
        function_name: { 'Ref' => 'Release' },
        definitions: Context.component.replace_variables(name => definition)
      )
    end

    @sns_subscription.each do |name, definition|
      pipeline_event_target = JsonTools.get(
        definition, 'Properties.Pipeline::EventTarget', '@deployed'
      )
      next unless pipeline_event_target == '@released'

      topic_arn = Context.component.replace_variables(
        JsonTools.get(definition, 'Properties.TopicArn')
      )

      delivery_policy = JsonTools.get(definition, 'Properties.DeliveryPolicy', {})
      filter_policy = JsonTools.get(definition, 'Properties.FilterPolicy', {})

      _process_sns_subscription(
        template: template,
        definitions: {
          "#{name}SnsSubscription" => {
            'Type' => 'AWS::SNS::Subscription',
            'Properties' => {
              'Endpoint' => { 'Ref' => 'Release' },
              'Protocol' => 'lambda',
              'TopicArn' => topic_arn,
              'DeliveryPolicy' => delivery_policy,
              'FilterPolicy' => filter_policy
            }
          }
        }
      )

      _process_lambda_permission(
        template: template,
        permissions: {
          "#{name}SnsSubscriptionPermission" => {
            "Properties" => {
              'Action' => 'lambda:InvokeFunction',
              'FunctionName' => { 'Ref' => 'Release' },
              'Principal' => 'sns.amazonaws.com',
              'SourceArn' => topic_arn
            }
          }
        }
      )
    end

    template
  end

  # Generates component specific Lambda function name
  # @return [String] Component specific lambda function name
  def _lambda_function_name
    sections = Defaults.sections
    [
      sections[:ams],
      sections[:qda],
      sections[:as],
      sections[:ase],
      sections[:branch],
      @component_name,
    ].join('-').gsub(/[^a-zA-Z0-9\-]/, '-')
  end

  # Generates component specific Lambda function stack name
  # @return [String] Component specific, latest lambda function stack name
  def _lambda_function_stack_name
    sections = Defaults.sections
    [
      sections[:ams],
      sections[:qda],
      sections[:as],
      sections[:ase],
      sections[:branch],
      @component_name,
      "Latest"
    ].join('-').gsub(/[^a-zA-Z0-9\-]/, '-')
  end

  # Generates component specific Lambda function release stack name
  # @return [String] Component specific, release stack name
  def _lambda_release_stack_name
    sections = Defaults.sections
    [
      sections[:ams],
      sections[:qda],
      sections[:as],
      sections[:ase],
      sections[:branch],
      @component_name,
      "Release"
    ].join('-').gsub(/[^a-zA-Z0-9\-]/, '-')
  end

  # Returns base trigger permission template for the lambda function
  # @param function_name [String] Logical resource name for Lambda function
  # @return [Hash] Base tempalte for AWS::Lambda::Permission resource required for the function
  def _base_service_permissions(function_name)
    {
      "S3ASBucketPermission" => {
        "Type" => "AWS::Lambda::Permission",
        "Properties" => {
          "Action" => 'lambda:InvokeFunction',
          "FunctionName" => { 'Ref' => "#{function_name}Version" },
          "Principal" => 's3.amazonaws.com',
          "SourceArn" => Context.s3.as_bucket_arn
        }
      },
      "S3ASBucketPermissionForDeployAlias" => {
        "Type" => "AWS::Lambda::Permission",
        "Properties" => {
          "Action" => 'lambda:InvokeFunction',
          "FunctionName" => { 'Ref' => 'Deploy' },
          "Principal" => 's3.amazonaws.com',
          "SourceArn" => Context.s3.as_bucket_arn
        }
      }
    }
  end

  # Downloads unpacks and uploads lambda artefact to a staging area for deployment
  # @param artefact_name [String] Artefact file name specified for the lambda function
  def _upload_package_artefact(artefact_name)
    download_artefact_bucket = Context.s3.artefact_bucket_name
    upload_artefact_bucket = Context.s3.lambda_artefact_bucket_name

    cd_artefact_path = Defaults.cd_artefact_path(component_name: @component_name)
    tmpdir = Dir.mktmpdir
    local_file_name = "#{tmpdir}/app.tar.gz"

    begin
      AwsHelper.s3_download_object(
        bucket: download_artefact_bucket,
        key: "#{cd_artefact_path}/app.tar.gz",
        local_filename: local_file_name
      )
      untgz!(local_file_name)
    rescue => e
      raise "Unable to download and unpack #{artefact_name} package " \
        "from #{download_artefact_bucket}/#{cd_artefact_path} - #{e}"
    end

    local_artefact_file_name = File.join tmpdir, artefact_name

    unless File.exist?(local_artefact_file_name)
      raise "Unable to locate #{artefact_name}. " \
        "Ensure lambda code is packaged as a single zip or jar artefact" \
        " into $PAYLOAD_DIR during the upload stage"
    end

    begin
      file_name = File.basename(local_artefact_file_name)
      Log.debug "Uploading file to #{upload_artefact_bucket}/#{cd_artefact_path}/#{file_name}"
      AwsHelper.s3_upload_file(
        upload_artefact_bucket, "#{cd_artefact_path}/#{file_name}", local_artefact_file_name
      )
    rescue => e
      raise "Unable to upload file to #{upload_artefact_bucket}/#{cd_artefact_path}/#{file_name} - #{e}"
    end
  rescue => e
    raise "Unable to unpack and upload lambda artefact #{artefact_name} - #{e}"
  ensure
    FileUtils.rm_rf tmpdir
  end
end
