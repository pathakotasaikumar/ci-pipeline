require "services/pipeline_metadata_service"

class PersistContext
  def initialize(state_storage, sections)
    @sections = sections
    @state_storage = state_storage

    @save_min_attempt_backoff = 3
    @save_max_attempt_backoff = 20
    @save_attempts_count = 5
  end

  def get_active_builds(component_name, build_number)
    context = _load_active_builds_context(component_name)

    return [] unless context["ActiveBuilds"]

    context["ActiveBuilds"][build_number] || []
  end

  def add_active_build(component_name, build_number, active_build_number)
    active_builds = []
    new_context = {}
    _update_active_builds_context(component_name) { |context|
      context["ActiveBuilds"] ||= {}
      context["ActiveBuilds"][build_number] ||= []
      context["ActiveBuilds"][build_number] << active_build_number unless context["ActiveBuilds"][build_number].include? active_build_number
      active_builds = context["ActiveBuilds"][build_number].clone
      new_context = context
    }
    begin
      Log.info "Updating the active build context into dynamoDB - add_active_build"
      new_context = nil if new_context.empty?
      PipelineMetadataService.save_metadata(
        context_name: _active_builds_path(component_name),
        context: new_context
      )
    rescue => e
      raise "Failed to update active builds for component #{component_name.inspect} - #{e}"
    end
    active_builds
  end

  def remove_active_build(component_name, build_number, active_build_number)
    active_builds = []
    new_context = {}

    _update_active_builds_context(component_name) { |context|
      next unless context["ActiveBuilds"]

      if !context["ActiveBuilds"].key?(build_number)
        # leave context alone (so not delete from dynamo) if build number is missing
        new_context = context
        next
      end

      context["ActiveBuilds"][build_number].delete(active_build_number)
      active_builds = context["ActiveBuilds"][build_number].clone
      context["ActiveBuilds"].delete(build_number) if context["ActiveBuilds"][build_number].empty?
      context.delete('ActiveBuilds') if context['ActiveBuilds'].empty?
      new_context = context
    }
    begin
      Log.info "Removing the active build context from dynamoDB"
      new_context = nil if new_context.empty?
      PipelineMetadataService.save_metadata(
        context_name: _active_builds_path(component_name),
        context: new_context
      )
    rescue => e
      raise "Failed to remove the active builds for component #{component_name.inspect} - #{e}"
    end
    active_builds
  end

  def released_build?
    Context.persist.released_build_number == Defaults.sections[:build]
  end

  # Function to find the released build number form the context
  # Function allow you to query the released build number from the dynamo context
  # which is introduced from QCP-1706. To read the context from dynamodb pass dynamo_context as true
  # in the method has variables
  # the arguments must be Hash value or can be empty
  # and the format of arguments released_build_number(build: 3, ams: ams01)
  # @param section_variables [Hash] target section variables
  def released_build_number(**section_variables)
    context = _load_release_context(**section_variables)
    context['ReleasedBuildNumber']
  end

  def released_build_number=(build_number)
    context = {}
    context['ReleasedBuildNumber'] = build_number unless build_number.nil?
    context = nil if context.empty?
    @state_storage.save(release_path, context)
    begin
      Log.info "Updating the release build context into dynamoDB"
      PipelineMetadataService.save_metadata(
        context_name: release_path,
        context: context
      )
    rescue => e
      raise "Failed to update released builds context - #{e}"
    end
  end

  def flush; end

  def _load_active_builds_context(component_name)
    Log.info "Loading active builds for component #{component_name.inspect}"
    @state_storage.load(_active_builds_path(component_name)) || {}
  end

  # backoff time in seconds for updating active builds context
  # @return (Integer) rand(@save_min_attempt_backoff..s@ave_max_attempt_backoff)
  def _get_backoff_sleep_time
    rand(@save_min_attempt_backoff..@save_max_attempt_backoff)
  end

  def _update_active_builds_context(component_name)
    attempt = 1
    saved = false
    while saved == false and attempt <= @save_attempts_count
      begin
        context = _load_active_builds_context(component_name)
        new_context = Marshal.load(Marshal.dump(context))
        yield(new_context)
        if new_context != context
          new_context = nil if new_context.empty?
          @state_storage.save(_active_builds_path(component_name), new_context)
        end
        saved = true
      rescue => e
        Log.info "Failed to save component persist context (attempt #{attempt}/#{@save_attempts_count}) - #{e}"
        sleep(_get_backoff_sleep_time) unless attempt == @save_attempts_count
      end
      attempt += 1
    end

    raise "Failed to update active builds for component #{component_name.inspect} after 3 attempts" if saved == false
  end

  def _active_builds_path(component_name)
    cleaned_name = component_name.gsub(/[^a-zA-Z0-9-]/, '-')
    [
      @sections[:ams],
      @sections[:qda],
      @sections[:as],
      @sections[:ase],
      @sections[:branch],
      cleaned_name,
      "ActiveBuilds"
    ]
  end

  # Constructing the release build path from the section variables
  # the arguments must be Hash value or can be empty
  # and the format of arguments release_path(build: 3, ams: ams01)
  # @return (Array)
  def release_path(**section_variables)
    release_path_variable = @sections.merge(section_variables)
    [
      release_path_variable[:ams],
      release_path_variable[:qda],
      release_path_variable[:as],
      release_path_variable[:ase].downcase,
      release_path_variable[:branch],
      "Release"
    ]
  end

  # Function to find the load the release context
  # the arguments must be Hash value or can be empty
  # and the format of arguments _load_release_context(build: 3, ams: ams01)
  # @param section_variables [Hash] target section variables
  def _load_release_context(**section_variables)
    Log.info "Loading release context"
    @state_storage.load(release_path(**section_variables)) || {}
  end
end
