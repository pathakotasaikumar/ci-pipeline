require 'consumables/aws/actions/http_request'
require 'pipeline/helpers/http'

class WaitForHttpResponse < HTTPRequest
  include Pipeline::Helpers::HTTP

  def initialize(component: nil, params: nil, stage: nil, step: nil)
    super

    @timeout = (params["Timeout"] || 900)
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
    
    raise "FAIL: Invalid request type specified - #{@request_type}" unless
        Pipeline::Helpers::HTTP.respond_to? request_method

    
    # 10 second delay between each try
    delay = 10
    max_attempts = (@timeout / 10.0).ceil
    
    # Minimum of 1 attempt
    max_attempts = [1, max_attempts].max

    (1..max_attempts).each do |attempt|
      Log.output "attemp: #{attempt} of #{max_attempts}"
      
      begin
        response = Pipeline::Helpers::HTTP.public_send(request_method, **args)
        valid_response_codes = @valid_codes.map!(&:to_s)
  
        if valid_response_codes.include? response.code.to_s
          Log.output "SUCCESS: Executed #{self.class} to #{@url} on #{@component.component_name}"
          return true
        else
          Log.error "FAIL: Executed #{self.class} to #{@url} on #{@component.component_name}"
        end
        Log.output "HTTP Response: #{response.body}"
      rescue => error
        Log.error "FAIL: Unable to execute #{self.class} to #{@url} on #{@component.component_name} - #{error}"
      end

      Log.output "sleeping for #{delay} seconds"
      sleep(delay) if attempt != max_attempts
    end

    raise "Timed out waiting to get success reponse" if stop_on_error?
  rescue => error
    Log.error "FAIL: Unable to execute #{self.class} to #{@url} on #{@component.component_name} - #{error}"
    raise "Unable to execute #{self.class} to #{@url} on #{@component.component_name} - #{error}" if stop_on_error?
  end
end
