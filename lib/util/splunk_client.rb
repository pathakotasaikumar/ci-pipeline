require 'uri'
require 'json'
require 'net/http'

# Helper class for Splunk related operations
class SplunkClient
  attr_reader :splunk_url, :splunk_token
  attr_accessor :http_connect_timeout

  # @param [string] url, Splunk server URL for HEC, such as 'http://splunk-server:8088/services/collector/event'
  # @param [string] token, Splunk HEC token
  def initialize(url:, token:)
    raise 'url is required' if url.to_s.empty?
    raise 'token is required' if token.to_s.empty?

    @splunk_url = url
    @splunk_token = token

    uri = URI.parse(@splunk_url)
    # noinspection RubyStringKeysInHashInspection
    header = {
      'Authorization' => "Splunk #{@splunk_token}"
    }

    @http_client = Net::HTTP.new(uri.host, uri.port)
    @http_request = Net::HTTP::Post.new(uri.request_uri, header)
  end

  # Sends data to Splunk asynchronously
  # use Thread[:output] to get result value
  # @return [Thread], use Thread[:output] to get resulting HTTPResponse object
  def send_data_async(data_hash)
    Thread.new { Thread.current[:output] = send_data(data_hash) }
  end

  # Sends data to Splunk synchronously
  # returns HTTPResponse objects
  # @param [Hash] data
  # @return [Boolean] success or failure
  def send_data(data)
    raise ArgumentError, 'Data argument must be a Hash instance' unless data.is_a?(Hash)

    @http_request.body = _prepare_payload(data)

    if !@http_connect_timeout.nil?
      Log.info "Using timeout: #{@http_connect_timeout}"
      @http_client.connect_timeout = @http_connect_timeout
    end

    response = @http_client.request(@http_request)

    return validate_response(response)
  rescue => e
    Log.warn "Unable to send request to #{splunk_url} - #{e}"
  end

  # Returns last operation success status
  # @return [Bool]
  def validate_response(response)
    if response.nil?
      Log.warn 'No response received'
      return false
    end

    unless response.is_a?(Net::HTTPResponse)
      Log.warn "Response is #{response.class.inspect}. Must be HTTPResponse"
      return false
    end

    if response.code.to_i != 200

      response_body = ''

      # fetching body and status from the failed response
      # we need these to get a better troubleshooting / logging experience over failed Splunk requests
      # body needs to be wrapped into begin-rescue as response object might be in a wrong state after fail
      begin
        response_body = response.body
      rescue => e
        response_body = "Couldn't get response body. Exception was:[#{e}]"
      end

      Log.warn "Unsuccessful received from Splunk. Http responce code:[#{response.code}] with body:[#{response_body}]"
      return false
    end

    JSON.parse(response.body)['text'] == 'Success'
  end

  private

  # logs message using Log class or falls back to puts() method
  # @param [string] message
  def _log(message)
    defined?(Log) ? Log.info(message) : puts(message)
  end

  # converts Hash to JSON representation
  # @param [Hash] data_hash
  def _prepare_payload(data_hash)
    raise 'data_hash has to be a Hash instance' unless data_hash.is_a?(Hash)

    payload = {}
    payload['event'] = data_hash || {}

    payload.to_json
  end
end
