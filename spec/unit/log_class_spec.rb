$LOAD_PATH.unshift("#{BASE_DIR}/lib")
require 'log_class'

require "#{LOGGING_SERVICES_DIR}/base_log_class.rb"
require "#{LOGGING_SERVICES_DIR}/colorized_log_class.rb"
require "#{LOGGING_SERVICES_DIR}/default_output_log_class.rb"
require "#{LOGGING_SERVICES_DIR}/snow_log_class.rb"
require "#{LOGGING_SERVICES_DIR}/splunk_log_class.rb"
require "#{LOGGING_SERVICES_DIR}/file_log_class.rb"

RSpec.describe LogClass do
  before(:all) do
    @splunk_url = ENV['bamboo_splunk_url']
    @splunk_token = ENV['bamboo_splunk_token_password']
  end

  def _get_logger
    logger = LogClass.new

    logger.instance_variable_set(:@appenders, [
                                   DefaultOutputLogClass.new
                                 ])

    logger
  end

  context 'General' do
    it '.new' do
      logger = _get_logger
      expect(logger).to be_truthy
    end
  end

  context '.name' do
    it 'returns value' do
      logger = _get_logger

      expect(logger.name).not_to eq(nil)
    end
  end

  context '.api' do
    it '.output' do
      logger = _get_logger
      message = _get_message

      result = _with_captured_stderr { logger.output message }
      expect(result).to include(message)
    end

    it '.debug' do
      logger = _get_logger
      message = _get_message

      result = _with_captured_stdout { logger.debug message }
      expect(result).to include(message)
    end

    it '.info' do
      logger = _get_logger
      message = _get_message

      result = _with_captured_stdout { logger.info message }
      expect(result).to include(message)
    end

    it '.warn' do
      logger = _get_logger
      message = _get_message

      result = _with_captured_stdout { logger.warn message }
      expect(result).to include(message)
    end

    it '.error' do
      logger = _get_logger
      message = _get_message

      result = _with_captured_stderr { logger.error message }
      expect(result).to include(message)
    end

    it '.fatal' do
      logger = _get_logger
      message = _get_message

      result = _with_captured_stderr { logger.fatal message }
      expect(result).to include(message)
    end
  end

  context 'ServiceNow' do
    it '.snow' do
      logger = _get_logger
      message = _get_message

      allow(ServiceNow).to receive(:log_message)

      result = _with_captured_stdout { logger.snow message }
      # with pipeline_log_debug=1 it would give more trace
      expect(result.include?("ServiceNow: #{message}\n")).to eq(true)
    end

    it '.snow fails' do
      logger = _get_logger
      message = _get_message

      allow(ServiceNow).to receive(:log_message) .and_raise('snow err!')

      result = _with_captured_stdout { logger.snow message }

      expect(result).to include("")
    end
  end

  context '._get_current_environment' do
    it 'returns prod on nil' do
      logger = _get_logger

      env = {

      }

      allow(logger).to receive(:_env).and_return(env)
      expect(logger.send(:_get_current_environment)).to eq("prod")
    end

    it 'returns prod on empty' do
      logger = _get_logger

      env = {
        "local_pipeline_unit_testing" => ""
      }

      allow(logger).to receive(:_env).and_return(env)
      expect(logger.send(:_get_current_environment)).to eq("prod")
    end

    it 'returns dev on non-empty' do
      logger = _get_logger

      env = {
        "local_pipeline_unit_testing" => 1
      }

      allow(logger).to receive(:_env).and_return(env)
      expect(logger.send(:_get_current_environment)).to eq("dev")
    end
  end

  context '._init_appenders_from_config' do
    it 'does not raise on error, should init appenders as is' do
      logger = _get_logger

      allow(logger).to receive(:_get_current_environment).and_raise('cannot get env')
      expect(logger).to receive(:_init_appenders_as_is).once

      expect {
        logger.__send__(:_init_appenders_from_config,
                        :appenders => {}, :config => {})
      }.not_to raise_error
    end
  end

  context '.get_config' do
    it 'returns default config' do
      logger = _get_logger

      expect(logger.get_config).to eq(logger.__send__(:_get_default_config))
    end
  end

  context '._init_appenders' do
    it 'init appenders as is - PROD' do
      logger = _get_logger

      env = {
        'local_pipeline_unit_testing' => nil
      }

      appenders = []

      allow(logger).to receive(:_env).and_return(env)
      allow(logger).to receive(:_get_logging_config).and_return(nil)

      logger.__send__(:_init_appenders, :appenders => appenders)

      # 4 default appended for prod
      expect(appenders.count).to eq(4)

      log_service_classes = appenders.map { |_| _.class }

      expect(log_service_classes).to include(FileLogClass)
      expect(log_service_classes).to include(DefaultOutputLogClass)
      expect(log_service_classes).to include(SnowLogClass)
      expect(log_service_classes).to include(SplunkLogClass)
    end

    it 'init appenders as is - DEV' do
      logger = _get_logger

      env = {
        'local_pipeline_unit_testing' => 'true'
      }

      appenders = []

      allow(logger).to receive(:_env).and_return(env)
      allow(logger).to receive(:_get_logging_config).and_return(nil)

      logger.__send__(:_init_appenders, :appenders => appenders)

      # 4 default appended for dev
      expect(appenders.count).to eq(2)

      log_service_classes = appenders.map { |_| _.class }

      expect(log_service_classes).to include(FileLogClass)
      expect(log_service_classes).to include(TokenizedColorLogClass)
    end

    it 'fills default PROD appenders' do
      logger = _get_logger

      env = {
        'local_pipeline_unit_testing' => nil
      }

      allow(logger).to receive(:_env).and_return(env)

      appenders = []
      logger.__send__(:_init_appenders, appenders: appenders)

      # default appended for prod
      expect(appenders.count).to eq(4)

      log_service_classes = appenders.map { |_| _.class }

      expect(log_service_classes).to include(FileLogClass)
      expect(log_service_classes).to include(DefaultOutputLogClass)
      expect(log_service_classes).to include(SnowLogClass)
      expect(log_service_classes).to include(SplunkLogClass)
    end

    it 'fills default DEV appenders' do
      logger = _get_logger

      env = {
        'local_pipeline_unit_testing' => true
      }

      allow(logger).to receive(:_env).and_return(env)

      appenders = []
      logger.__send__(:_init_appenders, appenders: appenders)

      # default appended for non-prod
      expect(appenders.count).to eq(4)

      log_service_classes = appenders.map { |_| _.class }

      expect(log_service_classes).to include(FileLogClass)
      expect(log_service_classes).to include(TokenizedColorLogClass)
      expect(log_service_classes).to include(SnowLogClass)
    end
  end

  context '._create_service_from_name' do
    it 'creates known services' do
      logger = _get_logger

      services = [
        FileLogClass.new,
        TokenizedColorLogClass.new,
        ColorizedLogClass.new,
        DefaultOutputLogClass.new,
        SnowLogClass.new,
        SplunkLogClass.new
      ]

      services.each do |service|
        service_class = service.class

        new_instance = logger.__send__(:_create_service_from_name, service_name: service.name)

        expect(new_instance).not_to eq(nil)
        expect(new_instance.class).to eq(service_class)
      end
    end

    it 'raises on unknown service' do
      services = [
        "1",
        "2"
      ]

      services.each do |service_name|
        expect {
          logger = _get_logger
          logger.__send__(:_create_service_from_name, service_name: service_name)
        }.to raise_error(RuntimeError, /Cannot find a log service for service_name: #{service_name}/)
      end
    end
  end

  context '._load_default_config' do
    it 'returns default JSON config' do
      logger = _get_logger

      expect(logger.__send__(:_load_default_config)).to eq(
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
      )
    end
  end

  context '._get_logging_config' do
    it 'loads config from ENV' do
      logger = _get_logger

      config = {
        "appenders" => {},
        "environments" => {}
      }

      env = {
        'bamboo_pipeline_log_config' => config.to_json
      }

      allow(logger).to receive(:_env).and_return(env)

      result = logger.__send__(:_get_logging_config)
      expect(result).to eq(config)
    end

    it "loads config from '.log.config' file" do
      logger = _get_logger

      file_config_path = File.join(Dir.pwd, '.log.config')
      file_config_string = File.read(file_config_path)
      config = JSON.parse(file_config_string)

      env = {
        'bamboo_pipeline_log_config' => nil
      }

      allow(logger).to receive(:_env).and_return(env)

      result = logger.__send__(:_get_logging_config)
      expect(result).to eq(config)
    end

    it "falls back to default config" do
      logger = _get_logger

      config = logger.__send__(:_load_default_config)

      env = {
        'bamboo_pipeline_log_config1' => config
      }

      allow(logger).to receive(:_default_logging_config_path).and_return('non-existing-file.file')
      allow(logger).to receive(:_env).and_return(env)

      result = logger.__send__(:_get_logging_config)
      expect(result).to eq(JSON.parse(config))
    end

    it 'does not raise on error' do
      logger = _get_logger

      allow(logger).to receive(:_parse_json_config).and_raise('cannot parse json!')
      expect(logger).to receive(:_log_error).once

      expect {
        result = logger.__send__(:_get_logging_config)
      }.not_to raise_error
    end
  end

  context '._output' do
    it 'returns noting' do
      logger = _get_logger

      result = logger.__send__(:_output, :debug, 'debug message')

      expect(result).to eq(nil)
    end

    it 'logs error' do
      logger = _get_logger

      allow(logger).to receive(:_invoke_appender).and_raise('Cannot invoke appender')
      expect(logger).to receive(:_log_error).once

      result = logger.__send__(:_output, :debug, 'debug message')

      expect {
        result
      }.not_to raise_error
    end
  end

  private

  def _get_message
    'message_' + Random.rand(1000).to_s
  end

  def _with_captured_stdout
    old_stdout = $stdout
    $stdout = StringIO.new('', 'w')
    yield
    $stdout.string
  ensure
    $stdout = old_stdout
  end

  def _with_captured_stderr
    old_stderr = $stderr
    $stderr = StringIO.new('', 'w')
    yield
    $stderr.string
  ensure
    $stderr = old_stderr
  end

  def _log(message)
    return if message.nil?

    defined?(Log) ? Log.info(message) : puts(message)
  end
end # RSpec.describe
