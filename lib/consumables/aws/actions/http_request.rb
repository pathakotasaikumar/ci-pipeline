require 'action'
require 'pipeline/helpers/http'

class HTTPRequest < Action
  include Pipeline::Helpers::HTTP

  def initialize(component: nil, params: nil, stage: nil, step: nil)
    super

    @url = params.fetch('URL', @url)
    raise ArgumentError, "URL parameter must be specified" if @url.nil?

    @type = params.fetch('Type', 'GET')
    Log.output "Type: #{@type}"
    @ssl = params.fetch('SSL', 'false')
    @headers = params.fetch('Headers', {})
    @payload = params.fetch('Payload', nil)
    @debug = params.fetch('Debug', nil)
    @valid_codes = params.fetch('ValidResponseCodes', [200])
    @stop_on_error = params.fetch('StopOnError', 'true').to_s

    @username = decrypt_secret('Username', params['Username']) unless params['Username'].nil?
    @password = decrypt_secret('Password', params['Password']) unless params['Password'].nil?
  end

  # @see Action#valid_stages
  def valid_stages
    [:all]
  end

  # @see Action#valid_components
  def valid_components
    [:all]
  end

  # @see Action#Invoke
  def invoke
    args = { url: Context.component.replace_variables(@url) }
    args[:user] = @username unless @username.nil?
    args[:pass] = @password unless @password.nil?
    args[:ssl] = ssl?
    args[:headers] = @headers unless @headers.nil?
    args[:data] = Context.component.replace_variables(@payload).to_json unless @payload.nil?

    Log.debug YAML.dump(args) if @debug

    request_method = @type.downcase.to_sym

    Log.output "request_method: #{request_method}"

    raise "FAIL: Invalid request type specified - #{@request_type}" unless
        Pipeline::Helpers::HTTP.respond_to? request_method

    response = Pipeline::Helpers::HTTP.public_send(request_method, **args)
    valid_response_codes = @valid_codes.map!(&:to_s)

    if valid_response_codes.include? response.code.to_s
      Log.output "SUCCESS: Executed #{self.class} to #{@url} on #{@component.component_name}"
    else
      Log.error "FAIL: Executed #{self.class} to #{@url} on #{@component.component_name}"
      raise "Status #{response.code} returned \n #{response.body}" if stop_on_error?
    end
    Log.output "HTTPRequest Response: #{response.body}"
  rescue => error
    Log.error "FAIL: Unable to execute #{self.class} to #{@url} on #{@component.component_name} - #{error}"
    raise "Unable to execute #{self.class} to #{@url} on #{@component.component_name} - #{error}" if stop_on_error?
  end

  private

  def decrypt_secret(label, base64_secret)
    AwsHelper.kms_decrypt_data(base64_secret)
  rescue => error
    raise "Unable to decrypt value specified for [#{label}]. "\
      "Ensure value provided is encrypted with application kms key - #{error}"
  end

  def ssl?
    @ssl.to_s == 'true'
  end

  def stop_on_error?
    @stop_on_error.to_s == 'true'
  end
end
