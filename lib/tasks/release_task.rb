require 'component'
require 'runner'

require_relative 'base_task'
require_relative 'teardown_task'

class ReleaseTask < BaseTask
  @context_task
  @teardown_task

  def name
    "release"
  end

  def check_state
    context_task.read

    if ["deployed", "released", "release_failed"].include? Context.pipeline.state
      Log.debug "Build is currently in state #{Context.pipeline.state.inspect}. Proceeding with release."
    else
      raise "Cannot perform release from current state #{Context.pipeline.state.inspect}"
    end
  end

  def check_service_now
    context_task.read
    ServiceNow.request_release
  end

  def load_components
    context_task.read

    # Load all of the components
    components = Context.pipeline.variable('components')

    # Instantiate consumables from these component definitions
    @consumables = Consumable.instantiate_all(components)
  end

  def pre_release_actions
    if Context.environment.variable('skip_actions', 'false') == 'true' ||
       Context.environment.variable('skip_release', 'false') == 'true'
      Log.snow "WARNING: Skipping actions execution"
      Log.warn "WARNING: Skipping actions execution"
    else

      # Run actions
      successful, failed = Runner.run_actions(@consumables, 'PreRelease')

      if failed.any?
        failed_actions = failed.map { |action| action.name }
        Log.snow "ERROR: Failed to run user defined actions: #{failed_actions.inspect}"
        raise "Failed to run user defined actions: #{failed_actions.inspect}"
      end
    end
  end

  def components
    load_components

    Log.info "Releasing components"
    successful, failed, extented_failed_state = Runner.release(@consumables)

    # Save results into the context
    Context.pipeline.set_variables({
      'release_successful_consumables' => successful.map { |consumable| consumable.definition },
      'release_failed_consumables' => failed.map { |consumable| consumable.definition },
    })

    if failed.any?
      raise _get_aggregate_failed_component_error(
        "Failed to release components: #{failed.map { |consumable| consumable.component_name }.inspect}",
        extented_failed_state
      )
    end
  end

  def post_release_actions
    if Context.environment.variable('skip_actions', 'false') == 'true' ||
       Context.environment.variable('skip_release', 'false') == 'true'
      Log.snow "WARNING: Skipping actions execution"
      Log.warn "WARNING: Skipping actions execution"
    else

      # Run actions
      successful, failed = Runner.run_actions(@consumables, 'PostRelease')

      if failed.any?
        failed_actions = failed.map { |action| action.name }
        Log.snow "ERROR: Failed to run user defined actions: #{failed_actions.inspect}"
        raise "Failed to run user defined actions: #{failed_actions.inspect}"
      end
    end
  end

  def release
    task_exception = nil

    check_state

    # report to Splunk
    # call after context:read as we need env vars set
    begin
      stage_stats = StatHelper.start_pipeline_stage(
        context: Context,
        stage_name: 'release'
      )
      Log.splunk_http(stage_stats)
    rescue => e
      Log.warn "Failed to report to Splunk - #{e} - #{e.backtrace}"
    end

    check_service_now

    begin
      load_components
      pre_release_actions
      components
      post_release_actions

      Context.pipeline.state = "released"
      ServiceNow.done_success
    rescue => e
      task_exception = e

      Log.error "Release has failed - #{e}"
      Log.error get_error_report(e)

      Context.pipeline.state = "release_failed"
      ServiceNow.done_failure

      # Clean up partial deployment
      if !_cleanup_after_release_failure?
        Log.error "Skipping cleanup (#{_release_failure_cleanup_flag_name} is set to false)"
      else
        Log.error "Cleaning up partial deployment (#{_release_failure_cleanup_flag_name} is set to true)"
        begin
          teardown_task.components
        rescue => e
          Log.error "Failed to perform cleanup - #{e}"
        end
      end

      raise e
    ensure
      # Save the context
      begin
          Log.info "Saving current context"
          context_task.write
      rescue => e
        Log.error "Failed to save the context - #{e}"
        end

      # report to Splunk
      begin
        exception_stats = StatHelper.exceptions_stats(task_exception)

        stage_stats = StatHelper.finish_pipeline_stage(
          context: Context,
          stage_name: 'release',
          additional_hash: exception_stats
        )

        Log.splunk_http(stage_stats)
      rescue => e
        Log.warn "Failed to report to Splunk - #{e} - #{e.backtrace}"
      end
    end
  end

  def context_task
    if @context_task.nil?
      @context_task = ContextTask.new
    end

    @context_task
  end

  def teardown_task
    if @teardown_task.nil?
      @teardown_task = TeardownTask.new
    end

    @teardown_task
  end

  private

  def _release_failure_cleanup_flag_name
    'bamboo_cleanup_after_release_failure'
  end

  def _cleanup_after_release_failure?
    !_env[_release_failure_cleanup_flag_name].nil? && _env[_release_failure_cleanup_flag_name].to_s == 'true'
  end
end
