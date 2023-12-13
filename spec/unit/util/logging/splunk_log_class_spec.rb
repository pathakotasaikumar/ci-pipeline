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
    SplunkLogClass.new
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

      expect(logger.name).to eq("splunk")
    end
  end

  context '.splunk_http' do
    it 'sends data' do
      logger = _get_instance

      dummy_splunk_client = double(SplunkClient)
      allow(logger).to receive(:_splunk_client).and_return(dummy_splunk_client)

      if logger.is_splunk_available?
        message = {
          :is_debug => true,
          :log_message => 'branch_name_' + rand(1000).to_s
        }

        allow(dummy_splunk_client).to receive(:send_data).and_return(true)

        result = nil

        expect {
          result = logger.splunk_http(message)
        }.not_to raise_error

        expect(result).to be(true)
      else
        _log_splunk_unavailable
      end
    end

    it 'fails sending data' do
      logger = _get_instance

      dummy_splunk_client = double(SplunkClient)
      allow(logger).to receive(:_splunk_client).and_raise('splunk is null')

      message = {
        :is_debug => true,
        :log_message => 'branch_name_' + rand(1000).to_s
      }

      allow(dummy_splunk_client).to receive(:send_data).and_return(true)

      result = nil

      expect {
        result = logger.splunk_http(message)
      }.not_to raise_error

      expect(result).to be(false)
    end

    it 'warns on splunk_client being not available' do
      logger = _get_instance

      allow(logger).to receive(:_splunk_client).and_return(nil)

      expect(Log).to receive(:warn).once

      expect(logger.splunk_http({})).to eq(false)
    end

    it 'returns nil splunk client' do
      logger = _get_instance

      allow(Defaults).to receive(:splunk_token_password).and_return(nil)
      allow(Defaults).to receive(:splunk_url).and_return(nil)

      expect(logger.__send__(:_splunk_client)).to eq(nil)
    end

    it 'returns splunk client' do
      logger = _get_instance

      allow(Defaults).to receive(:splunk_token_password).and_return("some-password")
      allow(Defaults).to receive(:splunk_url).and_return("http://splunk-local.local")

      expect(logger.__send__(:_splunk_client)).not_to eq(nil)
    end
  end

  private

  def _log_splunk_unavailable
    Log.warn 'Skipping Spunk integration test - splunk_url/splunk_token are empty.
        Set ENV["bamboo_splunk_url"]/ENV["bamboo_splunk_token_password"] variables'
  end
end
