require "#{LOGGING_SERVICES_DIR}/base_log_class.rb"
require "#{LOGGING_SERVICES_DIR}/colorized_log_class.rb"
require "#{LOGGING_SERVICES_DIR}/default_output_log_class.rb"
require "#{LOGGING_SERVICES_DIR}/snow_log_class.rb"
require "#{LOGGING_SERVICES_DIR}/splunk_log_class.rb"
require "#{LOGGING_SERVICES_DIR}/file_log_class.rb"

RSpec.describe BaseLogClass do
  def _get_instance
    ColorizedLogClass.new
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

      expect(logger.name).to eq('colorized_output')
    end
  end

  context '._should_output_message' do
    it 'returns false' do
      logger = _get_instance

      expect(
        logger.__send__(:_should_output_message?, :method => '', :message => nil)
      ).to eq(false)

      expect(
        logger.__send__(:_should_output_message?, :method => '', :message => '')
      ).to eq(true)

      expect(
        logger.__send__(:_should_output_message?, :method => '', :message => {})
      ).to eq(true)

      expect(
        logger.__send__(:_should_output_message?, :method => '', :message => [])
      ).to eq(true)

      expect(
        logger.__send__(:_should_output_message?, :method => '', :message => Object.new)
      ).to eq(true)
    end

    it 'returns true' do
      logger = _get_instance

      expect(
        logger.__send__(:_should_output_message?, :method => '', :message => "test")
      ).to eq(true)
    end
  end

  context '._lookup_color_for_method' do
    it 'falls back to white color' do
      logger = _get_instance

      allow(logger).to receive(:_lookup_color_from_config).and_raise('Cannot find color for message')

      expect(
        logger.__send__(:_lookup_color_for_method, :method => '11', :message => '22')
      ).to eq(37)
    end
  end

  context '.colors' do
    it 'returns colors' do
      logger = _get_instance

      expect(logger.__send__(:_white)).to eq(37)
      expect(logger.__send__(:_red)).to eq(31)
      expect(logger.__send__(:_green)).to eq(32)
      expect(logger.__send__(:_yellow)).to eq(33)
      expect(logger.__send__(:_blue)).to eq(34)
      expect(logger.__send__(:_pink)).to eq(35)
      expect(logger.__send__(:_light_blue)).to eq(36)
      expect(logger.__send__(:_light_blue)).to eq(36)
      expect(logger.__send__(:_gray)).to eq(37)
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
