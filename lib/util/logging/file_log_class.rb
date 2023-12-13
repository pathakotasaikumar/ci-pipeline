require 'logger'
require_relative 'base_log_class.rb'

class FileLogClass < BaseLogClass
  @logger

  def initialize
    super
  end

  def name
    "file_output"
  end

  private

  # override default _output method to get access to all default messages
  # be aware that :splunk_http and :snow come here as well
  def _output(method, message)
    # default
    composed_message = _compose_message(method: method, message: message)

    _logger.info composed_message
  end

  def _compose_message(method:, message:)
    thred_id   = _prepare_thred_id
    time_stamp = _prepare_timestamp(format: _time_format)

    method_value   = _prepare_method(method: method)
    message_value  = _prepare_message(message: message, method: method)

    "#{thred_id} #{time_stamp} #{method_value} #{message_value}"
  end

  def _prepare_message(message:, method:)
    # if _prepare_message is overwrittten, it is important to call super
    # base class handles formatting - :splunk_http message should be masked
    result = super
    result = result + "\n"

    result
  end

  def _get_default_config
    {
      "log_folder_path" => _default_log_folder,
      "log_file_name" => nil,
      "log_file_timestamp_format" => "%d_%m_%Y_%H_%M_%S"
    }
  end

  def _default_log_folder
    File.join(File.expand_path("..", Dir.pwd), "logs")
  end

  def _time_stamp_format
    config = get_config
    config.fetch("log_file_timestamp_format", "%d_%m_%Y_%H_%M_%S")
  end

  def _log_file_name
    config = get_config
    result = config.fetch("log_file_name", nil)

    if result == nil
      time_stamp = _prepare_timestamp(format: _time_stamp_format)
      result = "pipeline-#{time_stamp}.log"
    end

    result
  end

  def _log_path
    config = get_config
    folder_path = config.fetch("log_folder_path", _default_log_folder)

    begin
      FileUtils.mkdir_p folder_path
    rescue
    end

    File.join(folder_path, _log_file_name)
  end

  def _logger
    if @logger == nil
      _default_stdout_message(message: "Tracing pipeline output to: #{_log_path}")
      @logger = Logger.new(_log_path)

      @logger.formatter = proc do |severity, datetime, progname, msg|
        "#{msg}"
      end
    end

    @logger
  end
end
