# Helper class for stat related operations
module StatHelper
  extend self

  attr_accessor :secret_string

  # stores 'timer_name -> elapsed time' values for start_timer()/end_timer_in_seconds in seconds
  @@timers = {}

  # stores exception from the latest call
  @@last_finish_pipeline_stage_exception

  def self.get_last_finish_pipeline_stage_exception
    @@last_finish_pipeline_stage_exception
  end

  # starts new time tracking with provided name
  # use StatHelper.end_timer_in_seconds() with the same string to get elapsed time in seconds
  # @param [string] timer_name
  def start_timer(timer_name)
    Log.debug "STARTING: #{timer_name}"
    @@timers[timer_name] = Time.now
  end

  # returns time elapsed for the timer started with StatHelper.start_timer()
  # raises exception if timer with the giving name has not been started early
  # @param [string] timer_name
  # @return [float] time elapsed in seconds
  def end_timer_in_seconds(timer_name)
    Log.debug "ENDING: #{timer_name}"
    unless @@timers.has_key? timer_name
      # noinspection RubyQuotedStringsInspection
      raise "Cannot find timer by name #{timer_name}. "\
        "Call .start_timer(timer_name) before .end_timer_in_seconds(timer_name)"
    end
    Time.now - @@timers[timer_name]
  end

  # Fills provided hash with exception specific stat for Splunk reporting
  # Does nothing if exception is nil
  # @param [Exception] exception
  def exceptions_stats(exception)
    return {} if exception.nil?
    raise 'exception has to be an Exception instance' unless exception.is_a?(Exception)

    {
      error: {
        message: exception.to_s,
        exception_type: exception.class.to_s,
        exception_backtrace: exception.backtrace
      }
    }
  end

  def validate(hash)
    raise 'hash has to be a Hash instance' unless hash.is_a?(Hash)

    # TODO, we might validate presence of non-nullable vales in the hash before pushing to splunk
    hash
  end

  # Returns hash with env/context specific variables  Splunk reporting
  # Optional additional_hash will be merged into the final result returned
  # @param [ContextClass] context
  # @param [Hash] additional_hash
  # @return [Hash]
  def stats(context:, additional_hash: {})
    raise 'context has to be a ContextClass instance' unless context.is_a?(ContextClass)

    result = {
      deployment: _deep_clone(Defaults.sections.to_h),
      environment: _deep_clone(context.environment.variables.to_h),
      pipeline: _deep_clone(context.pipeline.variables.to_h)
    }

    _safe_hash_merge(result, _deep_clone(additional_hash)) unless additional_hash.nil?
    replace_nested_secrets(result, /password/)
    validate(result)
  end

  # merges two hashes into a single one recursively
  # @param [Hash] h1 source hash
  # @param [Hash] h2 destination hash
  def _safe_hash_merge(h1, h2)
    raise 'h1 has to be non-nil' if h1.nil?
    raise 'h2 has to be non-nil' if h2.nil?

    raise 'h1 has to be of Hash type' unless h1.is_a?(Hash)
    raise 'h2 has to be of Hash type' unless h2.is_a?(Hash)

    h2.keys.each do |key|
      if !h1.has_key? key
        h1[key] = h2[key]
      else
        self._safe_hash_merge h1[key], h2[key]
      end
    end
  end

  # Tracks pipeline statistic to Splunk
  # Wraps begin-rescue, never raises an exception
  # @param [ContextClass] context
  # @param [String] stage_name
  # @param [Hash] additional_hash
  def start_pipeline_stage(context:, stage_name:, additional_hash: {})
    raise 'context has to be a ContextClass instance' unless context.is_a?(ContextClass)
    raise 'stage_name has to be a String' unless stage_name.is_a?(String)

    stage_phase = 'started'
    stage_timer_name = stage_name + '_timer'
    StatHelper.start_timer(stage_timer_name)
    ci_executed_from = ENV["bamboo_BAMBOO_CI_EXEC"] || "github"

    data_hash = {
      general: {
        run_time_in_seconds: 0,
        rake_task_name: stage_name,
        rake_task_phase: stage_phase
      },
      executor: {
        ci_executed_from: ci_executed_from
      }
    }.merge(additional_hash)

    stats(context: context, additional_hash: data_hash)
  end

  # Sends stat data to Splunk if Splunk client is available
  # Optional additional_hash will be merged into the final result returned
  # Also tracks time under []
  # Never raises an exception, logs errors returning false or true
  # @param [ContextClass] context
  # @param [String] stage_name
  # @param [Hash] additional_hash
  def finish_pipeline_stage(context:, stage_name:, additional_hash: {})
    raise 'context has to be a ContextClass instance' unless context.is_a?(ContextClass)
    raise 'stage_name has to be a String' unless stage_name.is_a?(String)

    stage_phase = 'finished'
    stage_timer_name = stage_name + '_timer'
    elapsed_time = StatHelper.end_timer_in_seconds(stage_timer_name)

    # noinspection RubyStringKeysInHashInspection
    data_hash = {
      general: {
        run_time_in_seconds: elapsed_time,
        rake_task_name: stage_name,
        rake_task_phase: stage_phase
      }
    }.merge(additional_hash)

    stats(context: context, additional_hash: data_hash)
  rescue => e
    full_stage_name = stage_name.to_s + '_finished'
    Log.warn "start_pipeline_stage failed:[#{full_stage_name}] Failed to report to Splunk - #{e} "
    Log.debug e.backtrace

    @@last_finish_pipeline_stage_exception = e
  end

  # Secret string used to replace 'password' values
  # @return [String]
  def secret_string
    '******'
  end

  private

  def _deep_clone(obj)
    # noinspection RubyResolve
    Marshal.load(Marshal.dump(obj))
  end

  def replace_nested_secrets(object, pattern)
    if object.respond_to?(:key?)
      object.keys.each do |key|
        if key.to_s.downcase.match(Regexp.new(pattern))
          object[key] = secret_string if object[key].is_a?(String)
        else
          replace_nested_secrets(object[key], pattern)
        end
      end
    elsif object.is_a? Enumerable
      object.each { |obj| replace_nested_secrets(obj, pattern) }
    else
      object
    end
  end
end
