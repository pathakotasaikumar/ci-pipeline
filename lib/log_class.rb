require 'json'
require "#{LOGGING_SERVICES_DIR}/base_log_class.rb"
require "#{LOGGING_SERVICES_DIR}/colorized_log_class.rb"
require "#{LOGGING_SERVICES_DIR}/default_output_log_class.rb"
require "#{LOGGING_SERVICES_DIR}/snow_log_class.rb"
require "#{LOGGING_SERVICES_DIR}/splunk_log_class.rb"
require "#{LOGGING_SERVICES_DIR}/file_log_class.rb"
require "#{LOGGING_SERVICES_DIR}/tokenized_color_log_class.rb"

class LogClass < BaseLogClass
  @appenders

  def initialize
    super

    _log_std_debug "Created instance: LogClass"
    @appenders = []

    _init_appenders(appenders: @appenders)
  end

  def disable=(value)
    @appenders.each do |appender|
      begin
        appender.send('disable=', value)
      rescue => exception
        _log_error(error: "Cannot set disable status [#{value}] for appender: #{appender.inspect}")
      end
    end
  end

  private

  def _load_default_config
    {
      "environments": {
        "prod": {
          "appenders": {
            "default_stdout": {
              "type": "default_output",
              "enable": true
            },

            "default_file_output": {
              "type": "file_output",
              "enable": true
            },

            "splunk": {
              "type": "splunk",
              "enable": true
            },

            "snow": {
              "type": "snow",
              "enable": true
            }
          }
        },
        "dev": {
          "appenders": {
            "default_stdout": {
              "type": "tokenized_color_output",
              "config": {
                "enable": true,
                "color_map": {
                  "method": {
                    "debug": 36,
                    "info": 32
                  }
                },
                "tokens": {
                  "restrict": [
                    { "type": "method", "value": "debug" }
                  ]
                },
                "formatters": [
                  { "type": "method", "value": "debug", "format": "   {0}" }
                ]
              }
            },

            "default_file_output": {
              "type": "file_output",
              "config": {
                "enable": true
              }
            },

            "latest_file_output": {
              "type": "file_output",
              "config": {
                "enable": true,
                "log_file_name": "_pipeline-latest.log"
              }
            },

            "snow": {
              "type": "snow",
              "config": {
                "enable": true
              }
            }
          }
        }
      }
    }.to_json
  end

  def _default_logging_config_path
    if ENV['bamboo_pipeline_qa']
      File.join(Dir.pwd, '.log.config')
    else
      File.join(File.expand_path("..", Dir.pwd), '.log.config')
    end
  end

  def _load_default_file_config
    result = nil
    file_path = _default_logging_config_path

    if File.exist? file_path
      result = File.read(file_path)
    end

    result
  end

  def _get_logging_config
    result = nil

    # load config from env var
    _log_std_debug "  - loading config from ENV: bamboo_pipeline_log_config..."
    json_config = _env['bamboo_pipeline_log_config']

    if (json_config == nil || json_config.empty?)
      _log_std_debug "  - loading config from ENV: pipeline_log_config..."
      json_config = _env['pipeline_log_config']
    end

    # fallback to file based config
    if (json_config == nil || json_config.empty?)
      _log_std_debug "  - loading default config file..."
      json_config = _load_default_file_config
    end

    # fallback to default one
    if (json_config == nil || json_config.empty?)
      _log_std_debug "  - loading default in-memory config..."
      json_config = _load_default_config
    end

    # parse JSON config
    if (json_config != nil && !json_config.empty?)
      begin
        _log_std_debug "  - loading default in-memory config..."
        result = _parse_json_config(config: json_config)
      rescue => exception
        error_message = "Cannot load logging config: #{json_config} exception: #{exception}"

        _log_std_debug error_message
        _log_error(error: error_message)
      end
    end

    _log_std_debug "  - returning config as hash: #{json_config}"

    result
  end

  def _parse_json_config(config:)
    JSON.parse(config)
  end

  def _init_appenders_as_is(appenders:)
    # always save to file, use file log appender
    appenders << FileLogClass.new

    # dev - only console, colored appender
    # prod - file, bamboo, snow & splunk appenders

    if _is_pipeline_unit_testing
      # appenders << ColorizedLogClass.new
      appenders << TokenizedColorLogClass.new
    else
      appenders << DefaultOutputLogClass.new
      appenders << SnowLogClass.new
      appenders << SplunkLogClass.new
    end
  end

  def _get_current_environment
    _is_pipeline_unit_testing ? 'dev' : 'prod'
  end

  def _create_service_from_name(service_name:)
    _log_std_debug "Creating service from name: #{service_name}"

    case service_name
    when "file_output"
      FileLogClass.new
    when "tokenized_color_output"
      TokenizedColorLogClass.new
    when "colorized_output"
      ColorizedLogClass.new
    when "default_output"
      DefaultOutputLogClass.new
    when "snow"
      SnowLogClass.new
    when "splunk"
      SplunkLogClass.new
    else
      error_message = "Cannot find a log service for service_name: #{service_name}"

      _log_std_debug "ERROR - #{error_message}"
      raise error_message
    end
  end

  def _init_appenders_from_config(appenders:, config:)
    env = nil

    begin
      _log_std_debug "  - fetching env"
      env = _get_current_environment
      _log_std_debug "  - env is: #{env}"

      env_section = config["environments"][env]
      env_appenders_section = env_section["appenders"]

      env_appenders_section.each { |appender_name, appender_config|
        _log_std_debug "    - fetching type/config for appender: #{appender_name}"

        appender_type = appender_config["type"]
        appender_config = appender_config.fetch("config", {})

        _log_std_debug "    - creating instance for appender: #{appender_name}"
        appender_instance = _create_service_from_name(service_name: appender_type)

        if (appender_instance != nil)
          _log_std_debug "    -  configuring appender: #{appender_name}"

          # configure appender
          config_section = appender_config

          if (config_section != nil && !config_section.empty?)
            _log_std_debug "    -  calling set_config: #{appender_name}"
            appender_instance.send("set_config", config_section)
          else
            _log_std_debug "    -  skippig set_config: #{appender_name}"
          end

          appenders << appender_instance
        else
          _log_std_debug "    -  appender instance is NULL: #{appender_name}"
        end
      }
    rescue => exception
      error_message = "Couldn't configuire logging from config. Falling back to default logging config. Env: #{env} Config: #{config} Error: #{exception}"

      _log_std_debug "  error: #{error_message}"
      _log_error(error: error_message)

      _log_std_debug "  falling to as_is appender initialization"
      _init_appenders_as_is(appenders: appenders)
    end
  end

  def _init_appenders(appenders:)
    _log_std_debug "Configuring appenders"

    config = _get_logging_config

    if config != nil
      _log_std_debug "  - loading appenders from config"
      _init_appenders_from_config(appenders: appenders, config: config)
    else
      _log_std_debug "  - loading appenders as is"
      _init_appenders_as_is(appenders: appenders)
    end

    _log_std_debug "Configuring appenders completed"
  end

  def _invoke_appender(appender, method, message)
    _log_std_debug "Invoking appender: #{appender.name} #{appender.inspect}"

    if appender.respond_to?(method)
      _log_std_debug "  - appended responds to method: #{method.inspect}"
      appender.send(method, message)
    else
      _log_std_debug "  - appender #{appender} does not respond to method: #{method}"
    end

    _log_std_debug "Invoking appender completed: #{appender.inspect}"
  end

  def _output(method, message)
    @appenders.each do |appender|
      begin
        _invoke_appender(appender, method, message)
      rescue => appender_error
        begin
          _log_error(error: appender_error)
        rescue
        end
      end
    end

    # should return nil as some code returns Log.method() calls to other functions
    nil
  end
end
