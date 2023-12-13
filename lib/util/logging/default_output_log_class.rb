require_relative 'base_log_class.rb'

class DefaultOutputLogClass < BaseLogClass
  def initialize
    super

    $stdout.sync = true
    $stderr.sync = true
  end

  def name
    "default_output"
  end

  def output(message)
    _output_stream($stderr, "OUTPUT : #{message}\n")
  end

  def debug(message)
    _output_stream($stdout, "DEBUG : #{message}\n")
  end

  def info(message)
    _output_stream($stdout, "INFO  : #{message}\n")
  end

  def warn(message)
    _output_stream($stdout, "WARN  : #{message}\n")
  end

  def error(message)
    _output_stream($stderr, "ERROR : #{message}\n")
  end

  def fatal(message)
    _output_stream($stderr, "FATAL : #{message}\n")
  end

  def snow(message)
    _output_stream($stdout, "ServiceNow: #{message}\n")
  end

  def splunk_http(data_hash)
    _output_stream($stdout, "Splunk : [SPLUNK DATA]")
  end

  # override default implementation to avoid default message propogation
  def _output(method, message)
  end

  private

  def _output_stream(stream, message)
    return unless @disable != true
    return unless stream == $stdout || stream == $stderr

    stream.puts(message)
  end
end
