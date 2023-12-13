$LOAD_PATH.unshift("#{BASE_DIR}/lib")
require 'log_class'

require "#{LOGGING_SERVICES_DIR}/base_log_class.rb"
require "#{LOGGING_SERVICES_DIR}/colorized_log_class.rb"
require "#{LOGGING_SERVICES_DIR}/default_output_log_class.rb"
require "#{LOGGING_SERVICES_DIR}/snow_log_class.rb"
require "#{LOGGING_SERVICES_DIR}/splunk_log_class.rb"
require "#{LOGGING_SERVICES_DIR}/file_log_class.rb"

RSpec.describe BaseLogClass do
  def _get_instance
    BaseLogClass.new
  end

  context '.initialize' do
    it 'can create an instance' do
      logger = _get_instance

      expect(logger).to_not eq(nil)
    end
  end

  context '.@std_debug' do
    it 'false by default' do
      # clean this up before running tests
      ENV["pipeline_log_debug"] = nil
      ENV["bamboo_pipeline_log_debug"] = nil

      logger = _get_instance
      expect(logger.instance_variable_get(:@std_debug)).to eq(false)
    end

    it 'false cases' do
      ENV["pipeline_log_debug"] = nil
      ENV["bamboo_pipeline_log_debug"] = nil

      allow(ENV).to receive(:[]).with('pipeline_log_debug').and_return(nil)
      allow(ENV).to receive(:[]).with('bamboo_pipeline_log_debug').and_return(nil)

      logger = BaseLogClass.new
      expect(logger.instance_variable_get(:@std_debug)).to eq(false)

      allow(ENV).to receive(:[]).with('pipeline_log_debug').and_return("")
      allow(ENV).to receive(:[]).with('bamboo_pipeline_log_debug').and_return("")

      logger = BaseLogClass.new
      expect(logger.instance_variable_get(:@std_debug)).to eq(false)
    end

    it 'true cases' do
      ENV["pipeline_log_debug"] = nil
      ENV["bamboo_pipeline_log_debug"] = nil

      allow(ENV).to receive(:[]).with('pipeline_log_debug').and_return("1")
      allow(ENV).to receive(:[]).with('bamboo_pipeline_log_debug').and_return(nil)

      logger = BaseLogClass.new
      expect(logger.instance_variable_get(:@std_debug)).to eq(true)

      allow(ENV).to receive(:[]).with('pipeline_log_debug').and_return("")
      allow(ENV).to receive(:[]).with('bamboo_pipeline_log_debug').and_return(1)

      logger = BaseLogClass.new
      expect(logger.instance_variable_get(:@std_debug)).to eq(true)
    end
  end

  context '.name' do
    it 'returns default name' do
      logger = _get_instance

      expect(logger.name).to eq(logger.class.to_s.downcase)
    end
  end

  context '.public api' do
    it '.output redirects to _output' do
      logger = _get_instance

      expect(logger).to receive(:_output).with(:output, anything).once
      expect { logger.output('test') }.to_not raise_error
    end

    it '.debug redirects to _output' do
      logger = _get_instance

      expect(logger).to receive(:_output).with(:debug, anything).once
      expect { logger.debug('test') }.to_not raise_error
    end

    it '.info redirects to _output' do
      logger = _get_instance

      expect(logger).to receive(:_output).with(:info, anything).once
      expect { logger.info('test') }.to_not raise_error
    end

    it '.warn redirects to _output' do
      logger = _get_instance

      expect(logger).to receive(:_output).with(:warn, anything).once
      expect { logger.warn('test') }.to_not raise_error
    end

    it '.error redirects to _output' do
      logger = _get_instance

      expect(logger).to receive(:_output).with(:error, anything).once
      expect { logger.error('test') }.to_not raise_error
    end

    it '.fatal redirects to _output' do
      logger = _get_instance

      expect(logger).to receive(:_output).with(:fatal, anything).once
      expect { logger.fatal('test') }.to_not raise_error
    end

    it '.snow redirects to _output' do
      logger = _get_instance

      expect(logger).to receive(:_output).with(:snow, anything)
      expect { logger.snow('test') }.to_not raise_error
    end

    it '.splunk_http redirects to _output' do
      logger = _get_instance

      expect(logger).to receive(:_output).with(:splunk_http, anything)
      expect { logger.splunk_http('test') }.to_not raise_error
    end

    it '._output does nothing' do
      logger = _get_instance

      expect { logger.__send__(:_output, 'method', 'test') }.to_not raise_error
    end
  end

  context '.private api' do
    it '._prepare_thred_id' do
      logger = _get_instance

      expect(logger.__send__(:_prepare_thred_id)).to eq(Thread.current.object_id)
    end

    it '._prepare_thred_id' do
      logger = _get_instance

      expect(logger.__send__(:_time_format)).to eq("%d/%m/%Y %H:%M:%S")
    end

    it '._get_datetime' do
      logger = _get_instance

      expect(DateTime.now.new_offset(0) - logger.__send__(:_get_datetime) < 5).to eq(true)
    end

    it '._get_datetime' do
      logger = _get_instance

      time = DateTime.now.new_offset(4)
      time_format = "%m/%d/%Y %M:%H:%S"

      expected_value = time.strftime time_format
      allow(logger).to receive(:_get_datetime).and_return(time)

      expect(logger.__send__(:_prepare_timestamp, :format => time_format)).to eq(expected_value)
    end

    it '._default_stdout' do
      logger = _get_instance

      expect(logger.__send__(:_default_stdout)).to eq($stdout)
    end

    it '._default_stderr' do
      logger = _get_instance

      expect(logger.__send__(:_default_stderr)).to eq($stderr)
    end

    it '._env' do
      logger = _get_instance

      expect(logger.__send__(:_env)).to eq(ENV)
    end
  end

  context '._default_stderr_message' do
    it '._default_stderr_message' do
      logger = _get_instance

      expect { logger.__send__(:_default_stderr_message, :message => "_default_stderr_message") }.not_to raise_error
    end

    it '._default_stderr_message does not raise' do
      logger = _get_instance

      allow(logger).to receive(:_default_stderr).and_raise('cannot return _default_stderr')
      expect { logger.__send__(:_default_stderr_message, :message => "_default_stderr_message") }.not_to raise_error
    end
  end

  context '._default_stdout_message' do
    it '._default_stdout_message' do
      logger = _get_instance

      expect { logger.__send__(:_default_stderr_message, :message => "_default_stdout_message") }.not_to raise_error
    end

    it '._default_stdout_message does not raise' do
      logger = _get_instance

      allow(logger).to receive(:_default_stdout).and_raise('cannot return _default_stdout')
      expect { logger.__send__(:_default_stdout_message, :message => "_default_stdout_message") }.not_to raise_error
    end
  end

  context '.get_config' do
    it 'returns default config' do
      logger = _get_instance

      expect(logger.get_config).to eq(logger.__send__(:_get_default_config))
    end
  end

  context '.set_config' do
    it 'sets config custom config' do
      logger = _get_instance

      expect(logger.set_config({})).to eq(logger.__send__(:_get_default_config))
    end

    it 'handles nil value' do
      logger = _get_instance

      expect(logger.set_config(nil)).to eq(logger.__send__(:_get_default_config))
    end

    it 'merges configs' do
      logger = _get_instance

      config = {
        "a" => 1,
        "b" => 2,
        "custom" => {
          "1" => "2",
          "new" => {
            "c" => 3
          }
        }
      }

      expect(logger.set_config(config)).to eq(config)
    end

    it 'does not raise on error, fallback to default config' do
      logger = _get_instance

      allow(logger).to receive(:_merge_config).and_raise('Cannot merge!')
      expect(logger).to receive(:_get_default_config).at_least(:once)

      result = nil

      expect {
        result = logger.set_config({})
      }.not_to raise_error

      expect(result).to eq(logger.__send__(:_get_default_config))
    end
  end

  context '._log_error' do
    it 'logs error' do
      logger = _get_instance

      allow(logger).to receive(:_compose_error_message).and_return('error message')
      expect(logger).to receive(:_default_stdout_message).once

      result = logger.__send__(:_log_error, :error => 'error')
    end
  end

  context '.disable' do
    it 'does not raise error' do
      logger = _get_instance

      expect { logger.disable = true }.not_to raise_error
    end
  end

  context '.config' do
    it 'does not raise error' do
      logger = _get_instance

      expect { logger.config = {} }.not_to raise_error
    end
  end

  context '._prepare_message' do
    it 'returns values' do
      logger = _get_instance

      expect(logger.__send__(:_prepare_message, :message => nil, :method => '')).to eq('')
      expect(logger.__send__(:_prepare_message, :message => '1', :method => '')).to eq('1')
      expect(logger.__send__(:_prepare_message, :message => "2\n3", :method => '')).to eq('23')
      expect(logger.__send__(:_prepare_message, :message => {}, :method => '')).to eq('{}')
      expect(logger.__send__(:_prepare_message, :message => [], :method => '')).to eq('[]')
      expect(logger.__send__(:_prepare_message, :message => { "test" => "test_value" }, :method => '')).to eq('{"test"=>"test_value"}')
      expect(logger.__send__(:_prepare_message, :message => [1, 2, 3], :method => '')).to eq('[1, 2, 3]')
    end

    it 'masks :splunk_http' do
      logger = _get_instance

      expect(logger.__send__(:_prepare_message, :message => {}, :method => :splunk_http)).to eq('[SPLUNK DATA]')
    end
  end

  context '._prepare_method' do
    it 'returns value on nil' do
      logger = _get_instance

      expect(logger.__send__(:_prepare_method, :method => nil)).to eq('        :')
      expect(logger.__send__(:_prepare_method, :method => '1')).to eq('1       :')
      expect(logger.__send__(:_prepare_method, :method => "123456")).to eq('123456  :')
      expect(logger.__send__(:_prepare_method, :method => "123456789")).to eq('1234567 :')
    end

    it 'default values' do
      logger = _get_instance

      expect(logger.__send__(:_prepare_method, :method => :output)).to eq('OUTPUT  :')
      expect(logger.__send__(:_prepare_method, :method => :debug)).to eq('DEBUG   :')
      expect(logger.__send__(:_prepare_method, :method => :info)).to eq('INFO    :')
      expect(logger.__send__(:_prepare_method, :method => :warn)).to eq('WARN    :')
      expect(logger.__send__(:_prepare_method, :method => :error)).to eq('ERROR   :')
      expect(logger.__send__(:_prepare_method, :method => :fatal)).to eq('FATAL   :')
      expect(logger.__send__(:_prepare_method, :method => :snow)).to eq('SNOW    :')
      expect(logger.__send__(:_prepare_method, :method => :splunk_http)).to eq('SPLUNK  :')
    end
  end

  context '._compose_error_message' do
    it 'composes error message' do
      logger = _get_instance

      # nil
      result = logger.__send__(:_compose_error_message, :error => nil)
      expect(result).to eq('ERROR : LogClass error: unknown error')

      # non-exception
      result = logger.__send__(:_compose_error_message, :error => "some error")
      expect(result).to eq('ERROR : LogClass error: some error')

      # error class
      error = ArgumentError.new('param is null')

      result = logger.__send__(:_compose_error_message, :error => error)
      expect(result).to eq('ERROR : LogClass error: param is null - ')
    end
  end
end
