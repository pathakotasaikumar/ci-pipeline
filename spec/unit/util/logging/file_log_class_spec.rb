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
    FileLogClass.new
  end

  context '.initialize' do
    it 'can create an instance' do
      logger = _get_instance

      expect(logger).to_not eq(nil)
    end
  end

  context '.name' do
    it 'can create an instance' do
      logger = _get_instance

      expect(logger.name).to eq("file_output")
    end
  end

  context '._default_log_folder' do
    it 'returns default value' do
      logger = _get_instance

      expected_value = File.join(File.expand_path("..", Dir.pwd), "logs")

      expect(logger.__send__(:_default_log_folder)).to eq(expected_value)
    end
  end

  context '._log_path' do
    it 'returns default value' do
      logger = _get_instance

      env = {

      }

      log_file_name = 'my-log-file.log'

      allow(logger).to receive(:_log_file_name).and_return(log_file_name)
      allow(logger).to receive(:_env).and_return(env)

      expected_value = File.join(logger.__send__(:_default_log_folder), log_file_name)
      expect(logger.__send__(:_log_path)).to eq(expected_value)
    end
  end
end
