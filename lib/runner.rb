require 'json'
require 'util/thread_helper'
require 'component'
require 'consumable'
require 'consumables/asir_security'
require 'consumables/pipeline_kms_key'

module Runner
  extend self

  @@default_poll_time = 5.0
  @@teardown_poll_time = 10.0

  def run_actions_poll_time
    @@default_poll_time
  end

  def deploy_security_items_poll_time
    @@default_poll_time
  end

  def deploy_poll_time
    @@default_poll_time
  end

  def release_poll_time
    @@default_poll_time
  end

  def teardown_poll_time
    @@teardown_poll_time
  end

  def deploy_kms
    PipelineKmsKey.deploy
  end

  def load_persistence(components)
    released_build = Context.persist.released_build_number
    if released_build.nil?
      Log.output "There is currently no released build - no components will be persisted"
      return
    end

    Log.output "The currently released build is build #{released_build}"

    components.each do |name, component|
      next unless component.persist

      # Use the released build variables for this build
      if !Context.component.stack_id(name, released_build).nil? and !Context.component.build_number(name, released_build).nil?
        # Found this component's stack id and build number in the context - using persisted component
        Log.output "Component #{name.inspect} will be persisted from build #{Context.component.build_number(name, released_build)}"

        variables = Context.component.load_context(
          component_name: name,
          build_number: released_build
        )
        Context.component.set_all(variables)
      end
    end
  end

  def run_actions(components, stage)
    if !_run_actions?
      Log.info "Skipping running user defined actions on stage: #{stage}"
      return [[], []]
    end

    actions = {}
    components.values.each do |component|
      component.actions.each do |action|
        actions[action.stage] ||= {}
        actions[action.stage][action.step] ||= []
        actions[action.stage][action.step] << action
      end
    end
    successful_actions = []
    failed_actions = []
    (actions[stage] || {}).keys.uniq.sort.each do |step|
      thread_items = []
      actions[stage][step].each do |action|
        thread_items << {
          'action' => action,
          'thread' => Thread.new {
            begin
              Log.info "[#{stage}] : Executing action #{action.class.inspect} [#{action.component.component_name.inspect}]"
              action.invoke
            rescue => e
              Log.warn "[#{stage}] : Unable to invoke action #{action.class.inspect} #{e}"
              raise "[#{stage}] : Unable to invoke action #{action.class.inspect} #{e}"
            end
          }
        }
      end
      successful, failed = ThreadHelper.wait_for_threads(thread_items, run_actions_poll_time)
      successful_actions += successful.map { |item| item['action'] }
      failed_actions += failed.map { |item| item['action'] }
      # Break out if action in this stage has failed to invoke
      break unless failed_actions.empty?
    end
    return successful_actions, failed_actions
  end

  def deploy_security_items(components)
    Log.info "Deploying ASIR security items"

    if (!_deploy_security_items?)
      Log.info "Skipping deploying ASIR security items"
      return
    end

    # Determine the ASIR set from the first component that has the AsirSet key, default "latest"
    set_name = nil
    components.each do |name, component|
      if component.definition.has_key? 'AsirSet'
        set_name = component.definition['AsirSet']
        Log.info "Using ASIR set #{set_name.inspect} as defined in component #{name.inspect}"
        break
      end
    end
    if set_name.nil?
      set_name = "latest"
      Log.info "Using default ASIR set \"latest\""
    end

    Context.asir.set_name = set_name

    # Deploy ASIR security items
    AsirSecurity.deploy_security_items

    # Deploy ASIR security rules
    begin
      AsirSecurity.deploy_security_rules
    rescue => e
      Log.warn "Failed to update ASIR security rules. Deployment will continue"
      Log.warn "but ASIR security may not be up to date."
      Log.warn "#{e}\n" + e.backtrace.join("\n")
    end

    # Deploy component security items
    thread_items = []
    components.each do |name, component|
      # Skip persisted components
      next unless Context.component.build_number(name).nil?

      thread_items << {
        'component_name' => name,
        'component' => component,
        'thread' => Thread.new {
          component.deploy_security_items
        }
      }
    end

    successful, failed = ThreadHelper.wait_for_threads(thread_items, deploy_security_items_poll_time)

    if failed.any?
      failed.map! { |thread_item| thread_item['component_name'] }
      raise "Failed to deploy security items for components #{failed.inspect}"
    end
  end

  def deploy(components)
    # ensuring that we are under a valid deployment mode
    _validate_deploy_mode

    # Pre-populate known variables for all components into the context
    persisted_components = []
    components.each do |name, component|
      if Context.component.build_number(name).nil?
        Context.component.set_variables(name, { 'BuildNumber' => Defaults.sections[:build] })
        Context.component.set_variables(name, component.name_records)
      else
        persisted_components << name
      end
    end

    is_code_deploy = _is_codedeploy_deployment_mode?

    # Deploy each component, stage by stage
    stages = components.map { |name, component| component.stage }.uniq.sort

    successful_components = []
    failed_components = []
    extented_failed_state = []

    stages.each do |stage|
      Log.info "Deploying components in stage #{stage}"
      thread_items = []
      components.each do |name, component|
        # Skip component if it's not in the current stage
        next if component.stage != stage

        is_code_deploy_component = _is_codedeploy_component?(component: component)

        # skip non-codedeploy component in 'code_deploy' mode
        if (is_code_deploy == true) && (is_code_deploy_component != true)
          Log.info "Detected CodeDeploy deployment mode. Skipping non-AwsCodeDeploy component: #{component.class}"
          next
        end

        if !persisted_components.include? name
          # Component isn't persisted - deploy the component
          thread_items << {
            'component_name' => name,
            'component' => component,
            'thread' => Thread.new {
              if component.update_active_build?
                Context.persist.add_active_build(
                  name,
                  Defaults.sections[:build],
                  Defaults.sections[:build]
                )
              end
              component.pre_deploy
              component.deploy
              ServiceNow.create_ci(name)
              component.finalise_security_rules
              component.post_deploy
            }
          }
        else
          # Component is persisted - deploy only the security rules
          thread_items << {
            'component_name' => name,
            'component' => component,
            'thread' => Thread.new {
              if component.update_active_build?
                Context.persist.add_active_build(
                  name,
                  Context.component.build_number(name),
                  Defaults.sections[:build]
                )
              end
              component.pre_deploy
              component.finalise_security_rules
              component.post_deploy
              ServiceNow.create_ci(name)
            }
          }
        end
      end

      # Wait for all components in the current stage to finish deploying
      successful, failed = ThreadHelper.wait_for_threads(thread_items, deploy_poll_time)
      successful_components += successful.map { |item| item['component'] }
      failed_components += failed.map { |item| item['component'] }
      extented_failed_state += _get_extended_failed_state(failed)

      # Break out if a component in this stage has failed to deploy
      break unless failed_components.empty?
    end

    @@is_revision_error = _is_code_deploy_provision_error?(failed_components)

    return successful_components, failed_components, extented_failed_state
  end

  @@is_revision_error = nil;

  def _get_extended_failed_state(failed_thread_items = [])
    result = []

    if failed_thread_items.nil?
      failed_thread_items = []
    end

    failed_thread_items.each do |failedItem|
      result << _get_extended_component_thread_item(failedItem)
    end

    result
  end

  def _get_extended_component_thread_item(item)
    # ThreadHelper.wait_for_threads() enhances thread_items with the following values
    # - thread_item['status'] = :failed
    # - thread_item['exception'] = e
    # - thread_item['outputs'] = e.partial_outputs
    {
      :status => item['status'],
      :exception => item['exception'],
      :component_name => item['component_name'],
      :component => item['component']
    }
  end

  def is_codedeploy_revision_error?
    @@is_revision_error
  end

  def _is_code_deploy_provision_error?(failed_components)
    result = false

    # detect only in code deploy mode
    if !_is_codedeploy_deployment_mode?
      return false
    end

    # all failed components are CodeDeploy components
    codedeploy_components = failed_components.select { |c| _is_codedeploy_component?(component: c) }

    # if all failed components are codedeploy, set flag
    return codedeploy_components.count == failed_components.count
  end

  def release(components)
    successful_components = []
    failed_components = []
    extented_failed_state = []

    released_build = Context.persist.released_build_number
    if released_build.nil?
      Log.output "There is currently no released build"
    else
      Log.output "The currently released build is build #{released_build}"
    end

    if Context.environment.variable('skip_release', 'false') == 'true'
      # Skip release of all components
      Log.output "Skipping release of all components (skip_release = 'true')"
      Log.snow "Skipping release of all components (skip_release = 'true')"
      return successful_components, failed_components
    end

    Log.output "Releasing build #{Defaults.sections[:build]}"

    # Release components
    thread_items = []
    # Route53 Release DNS records template
    release_record_template = { "Resources" => {}, "Outputs" => {} }
    components.each do |name, component|
      # Release this component
      thread_items << {
        'component_name' => name,
        'component' => component,
        'thread' => Thread.new do
          Log.info "Releasing component #{name.inspect}"
          unless Defaults.ad_dns_zone?
            if component.respond_to?(:process_release_r53_dns_record)
              component.process_release_r53_dns_record(
                template: release_record_template,
                component_name: name,
                zone: Defaults.r53_hosted_zone
              )
            end
          end

          # Build AD DNS records regardless
          # @todo: Remove this once all teams are migrated to Route53
          if component.respond_to?(:create_ad_release_dns_records)
            component.create_ad_release_dns_records(component_name: name)
          end
          component.pre_release
          component.release
          component.post_release
        end
      }
    end

    successful, failed = ThreadHelper.wait_for_threads(thread_items, release_poll_time)

    if failed.any?
      Log.error "Failed to release one or more components. "\
        " This has likely left the release in a bad state. "\
        " It is recommended to retry, re-release the previous good build,"\
        " or manually remediate this situation."
    else
      unless Defaults.ad_dns_zone?
        deploy_r53_release_stack(template: release_record_template)
      end
      # Mark current build as the released build
      Context.persist.released_build_number = Defaults.sections[:build]
    end

    successful_components += successful.map { |item| item['component'] }
    failed_components += failed.map { |item| item['component'] }
    extented_failed_state += _get_extended_failed_state(failed)

    return successful_components, failed_components, extented_failed_state
  end

  def deploy_r53_release_stack(template: nil)
    stack_name = Defaults.dns_stack_name
    stack_id = AwsHelper.cfn_stack_exists(stack_name)

    if template.fetch('Resources', {}).empty?
      template['Resources']['NoResources'] = {
        'Type' => 'AWS::CloudFormation::WaitConditionHandle',
        'Properties' => {}
      }
    end

    params = {
      stack_name: stack_name,
      template: template,
      wait_delay: 10
    }

    if stack_id.nil?
      params[:tags] = Defaults.get_tags
      AwsHelper.cfn_create_stack(**params)
    else
      params[:max_attempts] = 30
      AwsHelper.cfn_update_stack(**params)
    end
  rescue => error
    raise "Failed to create/update Route53 release DNS stack - #{error}"
  end

  def teardown(components)
    released_build = Context.persist.released_build_number
    if released_build.nil?
      Log.output "There is currently no released build"
    else
      Log.output "The currently released build is build #{released_build}"
    end

    # Check whether we should be tearing this build down
    if Context.persist.released_build_number == Defaults.sections[:build]
      override_variable = 'force_teardown_of_released_build'

      if Context.environment.variable(override_variable, nil) == 'false'
        Log.snow "ERROR: Teardown of the released build is rejected by pipeline" \
                 " - variable #{override_variable.inspect} is set to \"false\""
        raise "ERROR: Teardown of the released build is rejected by pipeline" \
              " - variable #{override_variable.inspect} is set to \"false\""
      elsif Defaults.sections[:env] == "nonp"
        Log.output "Tearing down the currently released build - non-production build"
        Log.snow "Tearing down the currently released build - non-production build"
        Context.persist.released_build_number = nil
      elsif Context.environment.variable(override_variable, nil) == 'true'
        Log.output "Tearing down the currently released build" \
                   " - variable #{override_variable.inspect} is set to \"true\""
        Log.snow "Tearing down the currently released build" \
                 " - variable #{override_variable.inspect} is set to \"true\""
        Context.persist.released_build_number = nil
      else
        Log.snow "ERROR: Teardown rejected by pipeline" \
                 " - teardown was attempted on a currently-released production build"
        raise "Teardown rejected - teardown was attempted on a currently-released production build"
      end
    end

    # Remove this build from active builds
    thread_items = []
    components.each do |name, component|
      thread_items << {
        'component_name' => name,
        'component' => component,
        'thread' => Thread.new {
          begin
            active_builds = Context.persist.remove_active_build(
              name,
              Context.component.build_number(name),
              Defaults.sections[:build]
            )
            next active_builds
          rescue => e
            raise "Failed to remove active builds for component #{name.inspect} - #{e}"
          end
        }
      }
    end

    successful, failed = ThreadHelper.wait_for_threads(thread_items, teardown_poll_time)

    unless failed.empty?
      failed_components = failed.map { |item| item['component_name'] }
      Log.error "Failed to update active builds for components: #{failed_components.inspect}. Please contact the CSI team."
    end

    # Work out which components don't have any references so that we can tear them down
    components_to_teardown = {}
    successful.each do |item|
      component_name = item['component_name']
      component = item['component']
      active_builds = item['outputs'] || []
      if active_builds.empty?
        components_to_teardown[component_name] = component
      else
        Log.output "Skipping teardown of component #{component_name}" \
                   " - it is still referenced by builds #{active_builds.inspect}"
        Log.snow "Skipping teardown of component #{component_name}" \
                 " - it is still referenced by builds #{active_builds.inspect}"
      end
    end

    successful_components = []
    failed_components = []
    extented_failed_state = []

    # Tear down all unreferenced components, in reverse order of their deployment stage
    stages = components_to_teardown.values.map(&:stage).uniq.sort.reverse
    stages.each do |stage|
      Log.info "Tearing down components in stage #{stage}"

      # Teardown unreferenced components
      thread_items = []
      components_to_teardown.each do |name, component|
        # Skip component if it's not in the current stage
        next if component.stage != stage

        thread_items << {
          'component_name' => name,
          'component' => component,
          'thread' => Thread.new {
            begin
              Log.output "Tearing down component #{name}"
              Log.snow "Tearing down component #{name}"
              component.pre_teardown
              component.teardown
              component.post_teardown
            rescue => e
              raise "Teardown of component #{name.inspect} has failed - #{e}"
            end
          }
        }
      end

      successful, failed = ThreadHelper.wait_for_threads(thread_items, teardown_poll_time)
      successful_components += successful.map { |item| item['component'] }
      failed_components += failed.map { |item| item['component'] }
      extented_failed_state += _get_extended_failed_state(failed)
    end

    # Tear down all component's security rules (we build these each time even for persisted components)
    # Note that we can do this *after* tearing down the component because IAM reference integrity is not tracked
    thread_items = []
    components.each do |name, component|
      thread_items << {
        'component_name' => name,
        'component' => component,
        'thread' => Thread.new {
          begin
            Log.output "Tearing down security rules for component #{name.inspect}"
            component.teardown_security_rules
          rescue => e
            Log.warn "Failed to tear down security rules for component #{name.inspect} - #{e}"
          end
        }
      }
    end
    ThreadHelper.wait_for_threads(thread_items, teardown_poll_time)

    # Tear down unreferenced component's security items
    components_to_teardown.each do |name, component|
      thread_items << {
        'component_name' => name,
        'component' => component,
        'thread' => Thread.new {
          begin
            Log.output "Tearing down security items for component #{name.inspect}"
            component.teardown_security_items
          rescue => e
            raise "Failed to tear down security items for component #{name.inspect} - #{e}"
          end
        }
      }
    end

    successful, failed = ThreadHelper.wait_for_threads(thread_items, teardown_poll_time)
    successful_components += successful.map { |item| item['component'] }
    failed_components += failed.map { |item| item['component'] }
    extented_failed_state += _get_extended_failed_state(failed)

    # Clean up release DNS record if required
    if Context.persist.released_build_number == Defaults.sections[:build] or Context.persist.released_build_number.nil?
      # Delete dns stack
      begin
        stack_name = Defaults.dns_stack_name
        unless stack_name.nil?
          Log.info "Deleting Release DNS stack #{stack_name}"
          AwsHelper.cfn_delete_stack(stack_name)
        end
      rescue => error
        Log.warn "Failed to delete Release DNS stack #{stack_name} during teardown - #{error}"
      end
    end

    return successful_components.uniq, failed_components.uniq, extented_failed_state
  end

  private

  def _is_codedeploy_component?(component:)
    component.class.to_s == "AwsCodeDeploy"
  end

  # Checks if current provision mode is 'CodeDeploy'
  # @return [Boolean]
  def _is_codedeploy_deployment_mode?
    Defaults.is_codedeploy_deployment_mode?
  end

  # Checks and raises error if there is no released build
  # CodeDeploy requires a released build
  def _require_released_build_number
    # checking if CodeDeploy and we have got a released build
    if _is_codedeploy_deployment_mode? && Context.persist.released_build_number.nil?
      raise "CodeDeploy provision mode requires released build. Please release a build before running in CodeDeploy provision mode"
    end
  end

  # Validates if current deployment can be run based on deployment mode
  # For instance, 'CodeDeploy' provision mode requires released build
  def _validate_codedeploy_mode
    _require_released_build_number
  end

  # Checks if 'CodeDeploy' provision mode can be performed
  def _validate_deploy_mode
    _validate_codedeploy_mode
  end

  # Checks if security items need to be deployed
  # @return [Boolean]
  def _deploy_security_items?
    !_is_codedeploy_deployment_mode?
  end

  # Checks if user defined actions need to be deployed
  # @return [Boolean]
  def _run_actions?
    !_is_codedeploy_deployment_mode?
  end
end
