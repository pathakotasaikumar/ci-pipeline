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
    SnowLogClass.new
  end

  context '.initialize' do
    it 'can create an instance' do
      logger = _get_instance

      expect(logger).to_not eq(nil)
    end
  end

  context '.name' do
    it 'returns value' do
      logger = _get_instance

      expect(logger.name).to eq("snow")
    end
  end

  context '.snow' do
    it 'calls ServiceNow' do
      logger = _get_instance

      allow(ServiceNow).to receive(:log_message)
      expect(ServiceNow).to receive(:log_message).once

      expect { logger.snow('message') }.to_not raise_error
    end

    it 'raises on error' do
      logger = _get_instance

      allow(ServiceNow).to receive(:log_message).and_raise('Cannot call SNOW')
      expect(Log).to receive(:error).once

      expect { logger.snow('message') }.to_not raise_error
    end
  end
end
