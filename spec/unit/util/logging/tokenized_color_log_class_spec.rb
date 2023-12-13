require "#{LOGGING_SERVICES_DIR}/base_log_class.rb"
require "#{LOGGING_SERVICES_DIR}/colorized_log_class.rb"
require "#{LOGGING_SERVICES_DIR}/default_output_log_class.rb"
require "#{LOGGING_SERVICES_DIR}/snow_log_class.rb"
require "#{LOGGING_SERVICES_DIR}/splunk_log_class.rb"
require "#{LOGGING_SERVICES_DIR}/file_log_class.rb"

RSpec.describe BaseLogClass do
  def _get_instance
    TokenizedColorLogClass.new
  end

  context '.initialize' do
    it 'can create an instance' do
      logger = _get_instance

      expect(logger).to_not eq(nil)
    end
  end

  context '.name' do
    it 'returns name' do
      logger = _get_instance

      expect(logger.name).to eq('tokenized_color_output')
    end
  end

  context '.api' do
    it '.splunk_http' do
      logger = _get_instance
      message = _get_message

      result = _with_captured_stdout { logger.splunk_http message }
      expect(result).to include("[SPLUNK DATA]")
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
end
