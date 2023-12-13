class BaseLogClass
  attr_accessor :disable
  attr_accessor :config

  # controls raw output of the log class itself
  # logger needs to have a way to output messages
  # the following non-nil env variables are used to enable it
  # - pipeline_log_debug
  # - bamboo_local_pipeline_unit_testing
  @std_debug

  def initialize
    @splunk_client = nil
    @disable = false
    @config = nil

    @std_debug = _is_pipeline_log_debug
  end

  def name
    self.class.to_s.downcase
  end

  def output(message)
    _output(:output, message)
  end

  def debug(message)
    _output(:debug, message)
  end

  def info(message)
    _output(:info, message)
  end

  def warn(message)
    _output(:warn, message)
  end

  def error(message)
    _output(:error, message)
  end

  def fatal(message)
    _output(:fatal, message)
  end

  def snow(message)
    _output(:snow, message)
  end

  def splunk_http(data_hash)
    _output(:splunk_http, data_hash)
  end

  def get_config
    # return default config is nothing was set
    if (@config == nil || @config.empty?)
      return _get_default_config
    end

    @config
  end

  def set_config(value)
    # merge incoming value with default config
    # custom config overwrites all simple types
    # fallback to default config in case of error
    begin
      if (value != nil)
        @config = _merge_config(
          default_config: _deep_copy(_get_default_config),
          custom_config: _deep_copy(value)
        )
      else
        @config = _get_default_config
      end
    rescue => exception
      _log_error(error: "Couldn't merge logging config. Falling back to default config. Custom config: #{value} Error: #{exception}")
      @config = _get_default_config
    end
  end

  private

  def _null_or_empty(value)
    value.nil? || value.to_s.empty?
  end

  def _has_env_flag(value_name)
    !_null_or_empty(_env[value_name])
  end

  def _has_env_flags(value_names)
    value_names.each do |value_name|
      if !_null_or_empty(_env[value_name])
        return true
      end
    end

    false
  end

  def _is_pipeline_log_debug
    _has_env_flags([
                     'pipeline_log_debug',
                     'bamboo_pipeline_log_debug'
                   ])
  end

  def _is_pipeline_unit_testing
    _has_env_flags([
                     'local_pipeline_unit_testing',
                     'bamboo_local_pipeline_unit_testing'
                   ])
  end

  def _compose_error_message(error:)
    result = "ERROR : LogClass error"

    if (error != nil)
      result = result + ": #{error}"

      if error.respond_to?(:backtrace)
        result = result + " - #{error.backtrace}"
      end
    else
      result = result + ": unknown error"
    end

    result
  end

  def _log_error(error:)
    message = _compose_error_message(error: error)
    _default_stdout_message(message: message)
  end

  def _is_hash?(value)
    if (value != nil && value.is_a?(Hash))
      return true
    end

    return false
  end

  def _deep_copy(value)
    Marshal.load(Marshal.dump(value))
  end

  def _merge_config(default_config:, custom_config:)
    # overwrite only simple types by incoming custom config
    # that way inner hashes remain configiration

    custom_config.each { |new_key, new_value|
      has_value = default_config.keys.include? new_key

      if has_value
        # this is an existing value - poberride all but hash
        is_hash = _is_hash?(new_value)

        if is_hash
          _merge_config(
            default_config: default_config[new_key],
            custom_config: custom_config[new_key]
          )
        else
          default_config[new_key] = new_value
        end
      else
        # this is a new section coming from custom config
        default_config[new_key] = new_value
      end
    }

    default_config
  end

  def _get_default_config
    {}
  end

  def _output(method, message)
  end

  def _prepare_thred_id
    Thread.current.object_id
  end

  def _time_format
    "%d/%m/%Y %H:%M:%S"
  end

  def _get_datetime
    DateTime.now.new_offset(0)
  end

  def _prepare_timestamp(format:)
    _get_datetime.strftime format
  end

  def _prepare_method(method:)
    if method == :splunk_http
      method = :splunk
    end

    result = method.to_s.upcase

    # cutting first 7 chars
    # that gives indentation for the following verbs:
    # OUTPUT :
    # DEBUG  :
    # INFO   :
    # WARN   :
    # ERROR  :
    # FATAL  :
    # SNOW   :
    # SPLUNK :
    result += '       '
    result = result[0, 7] + " :"

    result
  end

  def _prepare_message(message:, method:)
    # with :splunk_http, message would be hash
    # by default other loggers use _prepare_message to format incoming string
    # replacing hash with "[SPLUNK DATA]" to reflect it in the output/filebase loggers
    if method == :splunk_http || method == :splunk
      message = "[SPLUNK DATA]"
    end

    if message == nil
      message = ''
    end

    message = message.to_s.gsub("\n", '')

    message
  end

  def _default_stdout
    $stdout
  end

  def _default_stderr
    $stderr
  end

  def _default_stdout_message(message:)
    begin
      return unless @disable != true

      _default_stdout.puts(message)
    rescue => e
      # switch to 'puts' bases trace if std output is broken
      _log_std_warning(message, e)
    end
  end

  def _default_stderr_message(message:)
    begin
      return unless @disable != true

      _default_stderr.puts(message)
    rescue => e
      # switch to 'puts' bases trace if std output is broken
      _log_std_warning(message, e)
    end
  end

  def _log_std_warning(message, error)
    puts "LOGDBG: Cannot put message into stdout/stderr: #{message}"
    puts "LOGDBG: Error was: #{error}"
  end

  # produces raw output using 'puts'
  # log classes should use this to output initialization/usage traces
  # use @std_debug flag to torn it on/off
  def _log_std_debug(message)
    if @std_debug

      thred_id = Thread.current.object_id
      time_stamp   = DateTime.now.new_offset(0).strftime("%d/%m/%Y %H:%M:%S")
      method_value = "LOGDBG  :"
      color_code   = 37

      puts "\e[#{color_code}m#{thred_id} #{time_stamp} #{method_value} #{message}\e[0m"
    end
  end

  def _env
    ENV
  end
end
