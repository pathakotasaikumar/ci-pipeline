require 'consumable'
require 'aws-sdk'
require 'json'

require_relative 'builders/codedeploy_application_builder'
require_relative 'builders/codedeploy_deploymentgroup_builder'

require File.expand_path("#{BASE_DIR}/lib/util/generate_password.rb")

class AwsCodeDeploy < Consumable
  include AwsCodeDeployApplicationBuilder
  include AwsCodeDeployDeploymentGroupBuilder

  @codedeploy_app
  @codedeploy_deployment_group

  @codedeploy_app_resource_name
  @codedeploy_related_component_name

  @deployment_group_name

  # @param (see Consumable#initialize)
  def initialize(component_name, definition)
    super(component_name, definition)

    @codedeploy_app = {}
    @codedeploy_deployment_group = {}

    @codedeploy_app_resource_name = nil
    @codedeploy_related_component_name = nil

    (definition['Configuration'] || {}).each do |name, resource|
      type = resource['Type']

      case type
      when 'AWS::CodeDeploy::Application'
        raise "This component does not support multiple #{type} resources" unless @codedeploy_app.empty?

        @codedeploy_app[name] = resource
      when 'AWS::CodeDeploy::DeploymentGroup'
        raise "This component does not support multiple #{type} resources" unless @codedeploy_deployment_group.empty?

        @codedeploy_deployment_group[name] = resource
      when "Pipeline::Features"
        @features[name] = resource
      when nil
        raise "Must specify a type for resource #{name.inspect}"
      else
        raise "Resource type #{type.inspect} is not supported by this component"
      end
    end

    @codedeploy_app_resource_name = @codedeploy_app.keys.first
    @codedeploy_deployment_group_resource_name = @codedeploy_deployment_group.keys.first

    @codedeploy_related_component_name = @codedeploy_app.values.first["Properties"]["ApplicationName"]

    raise 'Component requires at least one resource of type Pipeline::CodeDeploy::Application' if @codedeploy_related_component_name.empty?
    raise 'Component requires at least one resource of type Pipeline::CodeDeploy::DeploymentGroup' if @codedeploy_deployment_group_resource_name.empty?

    # clean '@' char, pipeline used '@component-name' to refer target component for codedeploy
    @codedeploy_related_component_name = @codedeploy_related_component_name.gsub('@', '')
  end

  # @return (see Consumable#security_items)
  def security_items
    region = Defaults.default_region

    [
      {
        'Name' => 'CodeDeployExecutionRole',
        'Type' => 'Role',
        'Component' => @component_name,
        'Service' => "codedeploy.#{region}.amazonaws.com"
      }
    ]
  end

  # @return (see Consumable#security_rules)
  def security_rules
    role_name = "#{@component_name}.CodeDeployExecutionRole"

    [
      # more limited copy of built-in AWSCodeDeployRole
      # arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole
      # in-place deployment only, we removed all terminate-delete permissions

      IamSecurityRule.new(
        roles: role_name,
        actions: [
          "autoscaling:CompleteLifecycleAction",
          "autoscaling:DeleteLifecycleHook",
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeLifecycleHooks",
          "autoscaling:PutLifecycleHook",
          "autoscaling:RecordLifecycleActionHeartbeat",
          "autoscaling:CreateAutoScalingGroup",
          "autoscaling:UpdateAutoScalingGroup",
          "autoscaling:EnableMetricsCollection",
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribePolicies",
          "autoscaling:DescribeScheduledActions",
          "autoscaling:DescribeNotificationConfigurations",
          "autoscaling:DescribeLifecycleHooks",
          "autoscaling:SuspendProcesses",
          "autoscaling:ResumeProcesses",
          "autoscaling:AttachLoadBalancers",
          "autoscaling:PutScalingPolicy",
          "autoscaling:PutScheduledUpdateGroupAction",
          "autoscaling:PutNotificationConfiguration",
          "autoscaling:PutLifecycleHook",
          "autoscaling:DescribeScalingActivities",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus",
          "tag:GetTags",
          "tag:GetResources",
          "sns:Publish",
          "cloudwatch:DescribeAlarms",
          "cloudwatch:PutMetricAlarm",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeInstanceHealth",
          "elasticloadbalancing:RegisterInstancesWithLoadBalancer",
          "elasticloadbalancing:DeregisterInstancesFromLoadBalancer",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:RegisterTargets",
          "elasticloadbalancing:DeregisterTargets"
        ],
        resources: "*"
      )
    ]
  end

  # Execute deployment steps for the component
  def deploy
    if Defaults.is_codedeploy_deployment_mode?
      Log.debug 'Skipping deploy stage in CodeDeploy mode'
      return
    end

    Log.debug 'Creating stack for CodeDeploy application'

    stack_outputs = {}
    begin
      stack_name = Defaults.component_stack_name(@component_name)
      tags = _get_tags

      template = _full_template

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
  end

  # override finalise_security_rules to avoid security updates in codedeploy mode
  def finalise_security_rules
    if Defaults.is_codedeploy_deployment_mode?
      Log.debug 'Skipping finalise_security_rules stage in CodeDeploy mode'
      return
    end

    super
  end

  # overrides base Consumable method to trigger codedeploy provision
  # this method is called after finalise_security_rules and gets called for both persistent and nonpersistent components
  # @return (see Consumable#post_deploy)
  def post_deploy
    if !Defaults.is_codedeploy_deployment_mode?
      Log.debug 'Skipping post_deploy stage in non-CodeDeploy mode'
      return
    end

    Log.info "Component: #{@component_name}, CodeDeploy provision mode detected"

    # fetching the latest release number or using the current one for the first release ever
    build_number = Context.persist.released_build_number || Defaults.sections[:build]

    Log.debug "Component: #{@component_name}, looking for CodeDeploy Deployment Group name for build: #{build_number}"

    group_name = Context.component.variable(@component_name, "CodeDeployReleaseGroupName", nil, build_number)
    app_name   = Context.component.variable(@component_name, "CodeDeployReleaseAppName", nil, build_number)

    Log.debug "Component: #{@component_name}, found group: #{group_name}, app name: #{app_name}"

    if group_name.nil? || app_name.nil?
      Log.info "Component: #{@component_name}, deployment group is null or empty. Perform 'release' stage first"
      return
    else
      Log.info "Component: #{@component_name}, deploying new revision, app: #{app_name}, group: #{group_name}"
      _deploy_revision(deployment_group_name: group_name, app_name: app_name)
    end
  end

  # overrides base Consumable method to avoid active updates in codedeploy mode
  def update_active_build?
    # skip active build update in codedeploy mode
    !Defaults.is_codedeploy_deployment_mode?
  end

  # Execute release for the component
  def release
    if Defaults.is_codedeploy_deployment_mode?
      Log.debug 'Skipping release stage in CodeDeploy mode'
      return
    end

    Log.debug "Ensuring CodeDeploy deployment group: #{_get_deployment_group_name}"
    stack_id = Context.component.variable(@component_name, "CodeDeployDeploymentGroupStackId", nil)
    template = _deploymentgroup_template

    if stack_id.nil?
      tags = _get_tags

      stack_name = Defaults.component_stack_name(_deploymentgroup_component_name)

      Log.debug "Stack does not exist, creating a new one: #{stack_name}"

      stack_outputs = AwsHelper.cfn_create_stack(
        stack_name: stack_name,
        template: template,
        tags: tags
      )

      # save additional stack info to use it with teardown later
      Context.component.set_variables(@component_name, {
        "CodeDeployDeploymentGroupStackId" => stack_outputs["StackId"],
        "CodeDeployDeploymentGroupStackName" => stack_outputs["StackName"],
        "CodeDeployReleaseAppName" => _get_application_name
      })
    else
      # stack exists, this component was persisted early
      # updating it with newly added deployment group
      Log.debug "Stack exists, updating: #{stack_id}"

      AwsHelper.cfn_update_stack(stack_name: stack_id, template: template)
    end

    # always update release number and group name
    # CodeDeploy remembers these values to use with revisions later on
    Context.component.set_variables(@component_name, {
      "CodeDeployReleaseNumber" => Defaults.sections[:build],
      "CodeDeployReleaseGroupName" => _get_deployment_group_name
    })
  end

  # Execute teardown for the component stack
  def teardown
    exception = nil

    # deployment group stack goes first
    begin
      Log.info "Deleting codedeploy deployment groups stack"

      stack_id = Context.component.variable(@component_name, "CodeDeployDeploymentGroupStackId", nil)
      AwsHelper.cfn_delete_stack(stack_id) unless stack_id.nil?
    rescue => e
      exception ||= e
      Log.warn "Failed to delete stack #{stack_id.inspect} during teardown - #{e}"
    end

    # codedeploy app stack
    begin
      Log.info "Deleting codedeplpy app stack"

      stack_id = Context.component.stack_id(@component_name)
      AwsHelper.cfn_delete_stack(stack_id) unless stack_id.nil?
    rescue => e
      exception ||= e
      Log.warn "Failed to delete stack #{stack_id.inspect} during teardown - #{e}"
    end

    raise exception unless exception.nil?
  end

  # overriding _update_security_rules to avoid security updates in CodeDeploy mode
  def _update_security_rules(rules: nil, skip_non_existant: true, create_empty: false)
    if Defaults.is_codedeploy_deployment_mode?
      Log.debug 'Skipping _update_security_rules stage in CodeDeploy mode'
      return
    end

    stack_name = Defaults.security_rules_stack_name(@component_name)
    stack_id   = AwsHelper.cfn_stack_exists(stack_name)

    if stack_id.nil?
      Log.info "Deploying security rules for CodeDeploy application #{@component_name.inspect}"
      super
    else
      Log.info "CodeDeploy application security rules exists. Skipping security rules update for component #{@component_name.inspect}"
    end
  end

  # Returns target component name which relates to the current CodeDeploy component
  # @return [String] name of the related component on which CodeDeploy works
  def get_target_component_name
    @codedeploy_related_component_name
  end

  private

  # returns component tags
  def _get_tags
    tags = Defaults.get_tags(@component_name)
    @pipeline_features.map { |f| tags += f.feature_tags }

    tags
  end

  # returns name of a stack which stores code deploy deployment groups
  def _deploymentgroup_component_name
    @component_name + "-DeploymentGroups"
  end

  # triggers codedeploy revision, checks progress and outcome
  # there is nearly no way to control revision deployment over CloudFormation templates
  def _deploy_revision(deployment_group_name:, app_name:)
    payload = _get_revision_deployment_payload(
      app_name: app_name,
      group_name: deployment_group_name
    )

    deployment_id = _trigger_revision_deployment(group_name: deployment_group_name, payload: payload)

    _trace_revision_deployment_result(deployment_id: deployment_id)
    _validate_revision_deployment_result(deployment_id: deployment_id)
  end

  # checks status of the codedeplode deployment
  def _validate_revision_deployment_result(deployment_id:)
    status =  AwsHelper.get_deployment_status(deployment_id: deployment_id)

    if status == "Succeeded"
      Log.info "Revision #{deployment_id} deployment completed, status: #{status}"
    else
      error_message = "Revision #{deployment_id} deployment failed, status: #{status}"

      Log.error error_message
      raise error_message
    end
  end

  # triggers codedeploy revision deployment
  def _trigger_revision_deployment(group_name:, payload:)
    Log.info "Creating new deployment for component: #{@component_name}, group: #{group_name}"
    deployment_id = AwsHelper.create_codedeploy_deployment(payload: payload)

    Log.info "  polling deployment with deployment_id: #{deployment_id} component: #{@component_name} group: #{group_name}"
    AwsHelper.wait_codedeploy_deployment(deployment_id: deployment_id)

    deployment_id
  end

  # fetches and outputs codedeploy revision deployment logs
  def _trace_revision_deployment_result(deployment_id:)
    Log.output "Fetching CodeDeploy logs..."

    deployment_instancies = AwsHelper.fetch_codedeploy_instancies(deployment_id: deployment_id)
    deployment_instancies.each do |deployment_instancies|
      _print_deployment_instance(deployment_id, deployment_instancies)
    end
  end

  # returns codedeploy deployment URL, it gets printed in the pipeline output
  # enables a one click link to get to the actual deployment
  def _get_deployment_url(deployment_id, region = nil)
    if region.nil?
      region = Defaults.default_region
    end

    "https://#{region}.console.aws.amazon.com/codedeploy/home?region=#{region}#/deployments/#{deployment_id}"
  end

  # formats codedeploy deployment logs in table format
  def _print_deployment_instance(deployment_id, deployment_instance)
    summary = deployment_instance.instance_summary
    deployment_url = _get_deployment_url(deployment_id)

    Log.output "Deployment id: #{deployment_id}, status: #{summary.status} \n#{deployment_url}"
    messages = []

    messages << [
      "deployment id",
      "event name",
      "status",
      "start time",
      "end time",
      "error code",
      "message"
    ]

    summary.lifecycle_events.each do |event|
      messages << [
        deployment_id,
        event.lifecycle_event_name,
        event.status,
        event.start_time,
        event.end_time,
        event.diagnostics == nil ? "" : event.diagnostics.error_code,
        event.diagnostics == nil ? "" : event.diagnostics.message
      ]
    end

    table_data = ObjToText.to_string_table messages
    table_data.each do |table_row|
      Log.output table_row
    end
  end

  # creates a codedeploy revision deployment paylod
  # AWS API is used to trigger deployments
  # https://docs.aws.amazon.com/sdkforruby/api/Aws/CodeDeploy/Client.html#create_deployment-instance_method
  def _get_revision_deployment_payload(app_name:, group_name:)
    # name convention for shared "00" branch specific bucket
    # cd/ams01/c031/211238/dev/master/00/codedeploy/11/rhel7/revision.tar.gz
    s3_location = {
      :bucket => _get_s3_bucket,
      :key => _get_s3_key,
      :bundle_type => _get_revision_archive_type
    }

    result = {
      :application_name => app_name,
      :deployment_group_name => group_name,
      :revision => {
        :revision_type => "S3",
        :s3_location => s3_location
      },
      # optionally, we might promote to the pipeline YAML component as an option
      # https://docs.aws.amazon.com/sdkforruby/api/Aws/CodeDeploy/Client.html#create_deployment-instance_method
      :file_exists_behavior => 'OVERWRITE'
    }

    result
  end

  # Returns branch-specific string based on current sections: ams-qda-as-ase-branch
  # @return [String] name prefix unique per branch
  def _app_branch_prefix
    sections = Defaults.sections

    [
      sections[:ams],
      sections[:qda],
      sections[:as],
      sections[:ase],
      sections[:branch]
    ].join('-')
  end

  # Returns component-specific string based on current sections: ams-qda-as-ase-branch-build-componentname
  # @return application name prefix unique per build and component
  def _app_name_prefix(custom_build: nil)
    sections = Defaults.sections
    build    = Defaults.sections[:build]

    if !custom_build.nil?
      build = custom_build
    end

    [
      _app_branch_prefix,
      build,
      @component_name
    ].join('-').gsub(/[^a-zA-Z0-9\-]/, '-')
  end

  # Returns build specific CodeDeploy application name
  def _get_application_name
    build = Defaults.sections[:build]

    if @persist == true
      Log.debug "Component marked as persist, checking is it was relesed previously"
      release_number = Context.persist.released_build_number

      # have we release previously?
      if (!release_number.nil? && Context.persist.released_build_number != build)
        Log.debug "Checking AWS stack, previous release number was: #{release_number}, current: #{build}"
        stack_id = Context.component.stack_id(@component_name, release_number)

        if !stack_id.nil?
          Log.debug "Found stack with id #{stack_id} for release build: #{release_number}, current: #{build}"
          build = release_number
        else
          Log.debug "Cannot find stack for release build: #{release_number}, current: #{build}"
        end
      else
        # never released previously
        Log.debug "Skipping, previous release number was: #{release_number}, current: #{build}"
      end
    end

    result =  _app_name_prefix(custom_build: build)
    Log.debug "Returning application name: #{result}"

    result
  end

  # Returns build specific CodeDeploy group name
  def _get_deployment_group_name
    sections = Defaults.sections
    build = Defaults.sections[:build]

    [
      _app_branch_prefix,
      build
    ].join('-').gsub(/[^a-zA-Z0-9\-]/, '-')
  end

  # Returns CloudFormation tempkate for codedeploy app
  def _full_template
    template = { 'Resources' => {}, 'Outputs' => {} }

    _process_codedeploy_application(
      template: template,
      resource_name: @codedeploy_app_resource_name,
      application_name: _get_application_name
    )

    template
  end

  # Returns CloudFormation tempkate for codedeploy deployment group
  def _deploymentgroup_template
    template = { 'Resources' => {}, 'Outputs' => {} }

    deployment_group_name = _get_deployment_group_name
    resource_eployment_group_name = deployment_group_name.gsub('-', '')

    group_template = _deployment_groups_template(custom_resource_name: resource_eployment_group_name)
    group_resource = group_template["Resources"][resource_eployment_group_name]

    template["Resources"][resource_eployment_group_name] = group_resource

    template
  end

  # Returns target S3 bucket to be used with codedeploy
  def _get_s3_bucket
    Context.s3.artefact_bucket_name
  end

  # Returns revision extension to be used with codedeploy
  def _get_revision_extension
    _is_windows_component? ? 'zip' : "tar.gz"
  end

  # Returns revision archive type to be used with codedeploy
  def _get_revision_archive_type
    _is_windows_component? ? 'zip' : 'tgz'
  end

  # Returns S3 key for the current codedeploy revison
  def _get_s3_key
    sections = Defaults.sections

    cd_common_artefact_path = Defaults.cd_common_artefact_path
    build_number = sections[:build]
    extension = _get_revision_extension

    "#{cd_common_artefact_path}/codedeploy/#{build_number}/#{@codedeploy_related_component_name}/revision.#{_get_revision_extension}"
  end

  # Checks if current component targets windows/linux component
  def _is_windows_component?
    target_definition = Consumable.get_consumable_definitions[@codedeploy_related_component_name]

    Defaults.codedeploy_win_component?(definition: target_definition)
  end

  # Forms codedeploy deployment group template for current build
  def _deployment_groups_template(existing_template: nil, custom_resource_name: nil)
    template = { 'Resources' => {}, 'Outputs' => {} }

    if existing_template
      template = existing_template
    end

    autoscaling_group_names = nil
    tag_filters = nil

    # fetching target autoscale group name if any
    # autoscale group name is persisted from the previous deployment and hence we can resolve it

    build = Context.component.build_number(@codedeploy_related_component_name) || Defaults.sections[:build]

    Log.debug "Fetching autoscale group name for build: #{build}, component: #{@codedeploy_related_component_name}"
    group_name = Context.component.variable(@codedeploy_related_component_name, 'AutoScalingGroupName', nil, build)
    Log.debug "component: #{@codedeploy_related_component_name}, build: #{build}, group name was: #{group_name}"

    if group_name.nil?
      tag_filters = _get_codedeploy_tags_by_name(
        component_name: @codedeploy_related_component_name
      )

      Log.info "Targeting instance component: #{@codedeploy_related_component_name}, target tags: #{tag_filters}"
    else
      autoscaling_group_names = [group_name]
      Log.info "Targeting autoscale component: #{@codedeploy_related_component_name}, target name: #{group_name}"
    end

    _process_codedeploy_deployment_group(
      template: template,
      resource_name: @codedeploy_deployment_group_resource_name,
      custom_resource_name: custom_resource_name,
      definition: @codedeploy_deployment_group,
      application_name: _get_application_name,
      service_role_arn: Context.component.role_arn(@component_name, 'CodeDeployExecutionRole'),
      ec2_tag_filters: tag_filters,
      autoscaling_group_names: autoscaling_group_names,
      deployment_group_name: _get_deployment_group_name,
      deployment_style: JsonTools.get(@codedeploy_deployment_group[@codedeploy_deployment_group_resource_name], "Properties.DeploymentStyle", {}),
      load_balancer_info: JsonTools.get(@codedeploy_deployment_group[@codedeploy_deployment_group_resource_name], "Properties.LoadBalancerInfo", {})
    )

    template
  end

  # Returns EC2 tag filter for codedeploy group
  def _get_codedeploy_tags_by_name(component_name:)
    # target component to update will always be either the latest released one or the current released one
    # code deploy is meant to be running after other components
    # hence, the latest build number for the target component should be the right onw

    Log.debug "Fetching persisted build number for component: #{@codedeploy_related_component_name}"
    build_number = Context.component.build_number(@codedeploy_related_component_name) || Defaults.sections[:build]

    Log.debug "component: #{@codedeploy_related_component_name} persisted build number: #{build_number}"

    related_component_name = [
      Defaults.branch_specific_id.join('-'),
      build_number,
      component_name
    ].join('-')

    # returning ex2 filter for codedeploy
    # name convention is used to get the right targets
    [
      {
        'Key' => 'Name',
        'Value' => related_component_name
      }
    ]
  end
end
