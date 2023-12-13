require 'component'
require 'runner'
require_relative 'base_task.rb'
require 'json'
require_relative '../consumables/aws/builders/dns_record_builder'
require_relative '../consumables/aws/builders/route53_record_builder'
require_relative '../util/thread_helper'

class TeardownTask < BaseTask
  @context_task

  def name
    "teardown"
  end

  def check_state
    context_task.read

    if ["deployed", "deploy_failed", "released", "release_failed", "teardown_failed", "torn_down", "start"].include? Context.pipeline.state
      Log.debug "Build is currently in state #{Context.pipeline.state.inspect}. Proceeding with teardown."
    else
      raise "Cannot perform teardown from current state #{Context.pipeline.state.inspect}"
    end
  end

  def check_service_now
    context_task.read
    ServiceNow.request_teardown
  end

  def list_active_builds(accepted_status)
    #accepted status pattern - ['UPDATE_ROLLBACK_COMPLETE', 'UPDATE_COMPLETE', 'CREATE_COMPLETE', 'ROLLBACK_COMPLETE', 'CREATE_FAILED', 'DELETE_FAILED']
    ab_prefix = [Defaults.sections[:ams], Defaults.sections[:qda], Defaults.sections[:as], Defaults.sections[:ase], Defaults.sections[:branch], "-"].join('-')
    comp_activebuilds = []
    ab_stack_name_list = AwsHelper.get_stack_list(ab_prefix, accepted_status).select{ |stack| stack =~ /-ActiveBuilds/ }

    ab_stack_name_list.each do |ab_stack_name|
      ab_template = AwsHelper.cfn_get_template(ab_stack_name)
      Log.info "#{ab_stack_name} : #{ab_template}"
      activebuilds_json = ab_template["Resources"]["Storage"]["Metadata"]["ActiveBuilds"]
      Log.info "Active Builds list - #{activebuilds_json}"

      #  Extracting comp name
      ab_stack_name_delim = ab_stack_name.split('-')
      ab_prefix.split('-').each do |element|
        ab_stack_name_delim.delete(element)
      end
      ab_stack_name_delim.delete('ActiveBuilds')
      component_name = ab_stack_name_delim.join('-')

      comp_activebuilds.push({
        "component": component_name,
        "all_active_builds_stats": activebuilds_json
      })
    end
    return comp_activebuilds
  end

  def gen_stack_persistance_stats
    #Extract the stack list based on the prefix
    prefix = [Defaults.sections[:ams], Defaults.sections[:qda], Defaults.sections[:as], Defaults.sections[:ase], Defaults.sections[:branch], Defaults.sections[:build]].join('-')
    accepted_status = ['UPDATE_ROLLBACK_COMPLETE', 'UPDATE_COMPLETE', 'CREATE_COMPLETE', 'ROLLBACK_COMPLETE', 'CREATE_FAILED', 'DELETE_FAILED']

    stack_name_list = AwsHelper.get_stack_list(prefix, accepted_status)
    Log.info "Stack list detected : #{stack_name_list}"

    active_builds_stats = list_active_builds(accepted_status)
    all_stack_stats = []
    stack_to_be_deleted = []

    stack_name_list.each do |stack_name|
      Log.info "+++  Analysing stack : #{stack_name} +++"

      #Extract component from stack_name
      stack_comp_name = AwsHelper.get_stack_comp_name(prefix, stack_name)
      Log.info "COMPONENT NAME: #{stack_comp_name}"

      if stack_name.include? "splunking"
        stack_stats = { "component": stack_comp_name, "all_active_builds_stats": {} }
        stack_stats[:stack_name] = stack_name
        is_comp_persistant = false
        stack_to_be_deleted.push(stack_name)
      else
        Log.info "active build stats : #{active_builds_stats}"

        if active_builds_stats.length != 0
          stack_stats = active_builds_stats.select{ |v| v[:component] == stack_comp_name }.first

          ## If build is part of the active build
          Log.info "COMPONENT ACTIVE BUILDS: #{stack_stats[:all_active_builds_stats]}"
        else
          stack_stats = { "component": stack_comp_name, "all_active_builds_stats": {} }
        end
        stack_stats[:stack_name] = stack_name

        if stack_stats[:all_active_builds_stats].key?("#{Defaults.build}")
          dep_build_list = stack_stats[:all_active_builds_stats].select{ |v| v == "#{Defaults.build}" }.values.first
          Log.info "BUILD DEPENDENTS on build #{Defaults.build}: #{dep_build_list}"

          #If activebuild is { "1": ["1"] }
          if dep_build_list.length == 1 && dep_build_list[0] == "#{Defaults.build}"
            is_comp_persistant = false
            stack_to_be_deleted.push(stack_name)

          #If activebuild is { "1": ["2"] } or { "1": [ "1", "2"] } or { "1": [ "2", "3"] }
          elsif ( dep_build_list.length == 1 && dep_build_list[0] != "#{Defaults.build}" ) || dep_build_list.length > 1
            if stack_name.include? "-Rules"
              is_comp_persistant = false
              stack_to_be_deleted.push(stack_name)
            else
              Log.output "Ignoring deleting the stack #{stack_name} as builds #{dep_build_list} is part of the dependent active builds #{Defaults.build}"
              is_comp_persistant = true
            end
          end
        else
          is_comp_persistant = false
          stack_to_be_deleted.push(stack_name)
        end
      end
      Log.info "-----------------------------------------------"
      stack_stats[:persistance] = is_comp_persistant
      all_stack_stats.push(stack_stats)
    end
    return all_stack_stats, stack_to_be_deleted
  end

  def gen_context_variables
    # Create a hash active_builds_stats having stack_name, active build stack, persistance
    all_stack_stats, stack_to_be_deleted = gen_stack_persistance_stats

    #Adding context to components
    components = {}
    all_stack_stats.each do |stackstats|
      component_name = stackstats[:component]
      component_definition = { "Type" => "", "Stage" => "", "Persist"=> stackstats[:is_comp_persistant] }
      components[component_name] = component_definition
      Context.pipeline.set_variables({ 'components' => components })
      Context.component.set_variables(component_name, { 'BuildNumber' => Defaults.sections[:build] })
    end
    Context.environment.set_variables({ 'skip_actions' => 'true' })
    Context.environment.set_variables({ 'is_teardown_failed' => 'true' })
    Context.environment.set_variables({ 'stack_to_be_deleted' => stack_to_be_deleted })
    Context.environment.set_variables({ 'all_stack_stats' => all_stack_stats })
  end

  def load_components
    begin
      context_task.read
      components = Context.pipeline.variable('components')
      if Context.environment.variable('is_teardown_failed', 'false') == 'false'
        Context.environment.set_variables({ 'is_teardown_failed' => 'false' })
        @consumables = Consumable.instantiate_all(components)
      end
    rescue RuntimeError => e
      Log.warn "Reading Context file has failed - #{e}"
      Context.environment.set_variables( "deployment_env" => (Defaults.sections[:env] == "prod") ? "Production" : "NonProduction" )

      #Do the teardown rescue only for nonproduction for now.
      if Context.environment.variable('deployment_env', 'Production') == 'Production'
        Context.pipeline.state = "teardown_failed"
        ServiceNow.done_failure
        raise e
      else
        Log.info "Applying workaround - Reading ActiveBuilds and deleting all other CFs which are not part of ActiveBuilds"
        gen_context_variables
      end
    rescue => e
      Context.pipeline.state = "teardown_failed"
      ServiceNow.done_failure
      raise e
    end
  end

  def pre_teardown_actions
    # Load user defined actions for the stage
    if Context.environment.variable('skip_actions', 'false') == 'true'
      Log.snow "WARNING: Skipping actions execution"
      Log.warn "WARNING: Skipping actions execution"
    else
      # Run actions
      successful, failed = Runner.run_actions(@consumables, 'PreTeardown')

      if failed.any?
        failed_actions = failed.map { |action| action.name }
        Log.snow "ERROR: Failed to run user defined actions: #{failed_actions.inspect}"
        raise "Failed to run user defined actions: #{failed_actions.inspect}"
      end
    end
  end

  def components
    load_components

    Log.info "Tearing down components"
    if Context.environment.variable('is_teardown_failed', 'false') == 'false'
      successful, failed, extented_failed_state = Runner.teardown(@consumables)

      # Save results into the context
      Context.pipeline.set_variables({
        'teardown_successful_consumables' => successful.map { |consumable| consumable.definition },
        'teardown_failed_consumables' => failed.map { |consumable| consumable.definition }
      })

      if failed.any?
        raise _get_aggregate_failed_component_error(
          "Failed to tear down components: #{failed.map { |consumable| consumable.component_name }.inspect}",
          extented_failed_state
        )
      end

    else

      # Remove this build from active builds in dynamodb
      all_components = []
      Log.info "All stacks detected : #{Context.environment.variable('all_stack_stats', [])}"
      Context.environment.variable('all_stack_stats', []).each do |stackstat|
        component_name = stackstat[:component]
        if !all_components.include? "#{component_name}"
          begin
            all_components = all_components + [component_name]
            active_builds = Context.persist.remove_active_build(
              component_name,
              Context.component.build_number(component_name),
              Defaults.sections[:build]
            )
            next active_builds
          rescue => e
            raise "Failed to remove active builds for component #{name.inspect} - #{e}"
          end
        end
      end

      Log.info "All components non persistent detected: #{all_components}"

      #Delete the DNS records
      all_components.each do |component|
        #clean up DNS records dynamo.teardwn.dev.c031-01.ams01.nonp.qcpaws.qantas.com.au to dynamo.teardwn-27.dev.c031-01.ams01.nonp.qcpaws.qantas.com.au
        dns_name = [component, Defaults.sections[:branch]+ "-" + Defaults.sections[:build],  Defaults.sections[:qda] + "-" + Defaults.sections[:as], Defaults.sections[:ams], 'nonp', 'qcpaws.qantas.com.au'].join('.')
        begin
          Util::Nsupdate.delete_dns_record(dns_name) unless dns_name.nil?
        rescue => error
          Log.error "Failed to delete deployment DNS record #{dns_name} - #{error}"
          raise "Failed to delete deployment DNS record #{dns_name} - #{error}"
        end
      end

      #Deleting the stacks
      stack_to_be_deleted = Context.environment.variable('stack_to_be_deleted', [])

      Log.info "+++ DELETING THE STACKS +++"
      Log.info "Stacks to be deleted: #{stack_to_be_deleted}"
      if stack_to_be_deleted.uniq.length > 0
        #Getting the rules stack first and delete them
        stack_to_be_deleted.uniq.each do |stack_name|
          if stack_name.include? "-Rules"
            AwsHelper.cfn_delete_stack(stack_name, true, [])
            stack_to_be_deleted.delete(stack_name)
          end
        end

        #Deleting the rest of the stacks
        stack_to_be_deleted.uniq.each do |stack_name|
          Log.info "Deleting the stack : #{stack_name} as there is no persistance dependencies"
          AwsHelper.cfn_delete_stack(stack_name, true, [])
        end
      else
        Log.info "No Stacks detected to be deleted"
      end
      Log.info "--------------------------"
    end
  end

  def post_teardown_actions
    # Load user defined actions for the stage
    if Context.environment.variable('skip_actions', 'false') == 'true'
      Log.snow "WARNING: Skipping actions execution"
      Log.warn "WARNING: Skipping actions execution"
    else

      # Run actions
      successful, failed = Runner.run_actions(@consumables, 'PostTeardown')

      if failed.any?
        failed_actions = failed.map { |action| action.name }
        Log.snow "ERROR: Failed to run user defined actions: #{failed_actions.inspect}"
        raise "Failed to run user defined actions: #{failed_actions.inspect}"
      end
    end
  end

  def teardown
    Defaults.set_pipeline_task('teardown')
    task_exception = nil

    check_state

    # report to Splunk
    # call after context:read as we need env vars set
    begin
      stage_stats = StatHelper.start_pipeline_stage(
        context: Context,
        stage_name: 'teardown'
      )
      Log.splunk_http(stage_stats)
    rescue => e
      Log.warn "Failed to report to Splunk - #{e} - #{e.backtrace}"
    end

    check_service_now

    begin
      load_components
      pre_teardown_actions
      components
      post_teardown_actions

      Context.pipeline.state = "torn_down"
      ServiceNow.done_success
    rescue => e
      task_exception = e

      Log.error "Teardown has failed - #{e}"
      Log.error get_error_report(e)

      Context.pipeline.state = "teardown_failed"
      ServiceNow.done_failure
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
          stage_name: 'teardown',
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
end
