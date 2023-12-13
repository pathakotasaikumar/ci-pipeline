require 'defaults'
require "#{BASE_DIR}/lib/util/splunk_client.rb"
require_relative 'base_log_class.rb'

class SplunkLogClass < BaseLogClass
  @splunk_client

  def initialize
    super
  end

  def name
    "splunk"
  end

  # override default implementation to avoid message propogation
  def _output(method, message)
  end

  # Sends data to Splunk (if Splunk client is available)
  # Does not raise an exception, writes message to a log
  # Returns true/false value
  # @param [Hash] data_hash
  # @return [Boolean]
  def splunk_http(data_hash)
    begin
      _log_std_debug "splunk splunk_http: data_hash: #{data_hash.inspect}"

      if _splunk_client.nil?
        splunk_client_message = 'Splunk client is not available. Set environment variables'

        _log_std_debug splunk_client_message
        Log.warn splunk_client_message

        return false
      else
        _log_std_debug "    - _splunk_client is not nil"
      end

      _log_std_debug "    - sending data..."
      success = _splunk_client.send_data(data_hash)
      warn 'Failed to send data to Splunk' unless success

      _log_std_debug "    - result: #{success}"

      success
    rescue => e
      error_message = "Error while sending data to Splunk - #{e} - #{e.backtrace}"

      _log_std_debug "    - error: #{error_message}"
      Log.error error_message

      return false
    end
  end

  def is_splunk_available?
    _splunk_client != nil
  end

  private

  def _splunk_client
    if @splunk_client == nil
      if !Defaults.splunk_token_password.nil? && !Defaults.splunk_url.nil?

        _log_std_debug "    - creating new SplunkClient"

        @splunk_client = SplunkClient.new(
          url: Defaults.splunk_url,
          token: Defaults.splunk_token_password
        )

        _log_std_debug "    - created new SplunkClient"
      else
        _log_std_debug "    - splunk_token_password or splunk_url are nil"
      end

    end

    @splunk_client
  end
end
