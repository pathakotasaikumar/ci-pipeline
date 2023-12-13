require 'json'

ServiceNowResponse = Struct.new(:code, :payload, :message)

class ServiceNowApi
  # initializes a new instance of ServiceNowApi class
  # @param enabled [Boolean] enables SNOW server integration by invoking HTTP endpoint
  # @param endpoint [String] SNOW user name
  # @param username [String] SNOW user password
  # @param proxy [String] proxy endpoint
  # @param build_user [String] build user name to pass into SNOW metadata, it's Qantas ID of the user who triggered the CI/CD build
  # @param request_action [String] action name to perform against SNOW server
  def initialize(
    enabled: true,
    endpoint:,
    username:,
    password:,
    proxy: nil,
    build_user: nil,
    request_action: nil
  )

    @enabled = enabled

    if enabled
      # Required parameters
      @endpoint = endpoint
      @username = username
      @password = password

      # Optional parameters
      @proxy = proxy
      @build_user = build_user
    end

    @action = request_action
  end

  # checks if DEPLOY action is allowed, raises error otherwise
  # @return [Hash] HTTP response payload as hash
  def request_deploy
    if !@enabled
      return _trace_disabled_state(message: 'ServiceNow ALM integration is DISABLED - proceeding with deployment')
    end

    response = _request_action('qanc_create_update')
    raise "ServiceNow rejected the request to perform a deployment: #{response.code} - #{response.message}" unless response.code == "OK"

    return response
  end

  # checks if RELEASE action is allowed, raises error otherwise
  # @return [Hash] HTTP response payload as hash
  def request_release
    if !@enabled
      return _trace_disabled_state(message: 'ServiceNow ALM integration is DISABLED - proceeding with release')
    end

    response = _request_action('qanc_release')
    raise "ServiceNow rejected the request to perform a release: #{response.code} - #{response.message}" unless response.code == "OK"

    return response
  end

  # checks if TEARDOWN action is allowed, raises error otherwise
  # # @return [Hash] HTTP response payload as hash
  def request_teardown
    if !@enabled
      return _trace_disabled_state(message: 'ServiceNow ALM integration is DISABLED - proceeding with teardown')
    end

    response = _request_action('qanc_teardown')
    raise "ServiceNow rejected the request to perform a teardown: #{response.code} - #{response.message}" unless response.code == "OK"

    return response
  end

  # logs message to SNOW server by invoking 'create_note' action
  # @param message [String] message to be logged
  # @return [Hash] HTTP response payload as hash
  def log_message(message)
    return nil if @action.nil? || !@enabled

    response = _query(
      action: @action,
      state: "update",
      snow_id: Context.pipeline.snow_change_id,
      payload: JSON.dump({ "action" => "create_note", "message" => message }),
    )

    return response
  end

  # creates or updates CI notes for particular plan/component by invoking 'create_ci' action
  # @param component_name [String] component to be logged
  # @return [Hash] HTTP response payload as hash
  def create_ci(component_name)
    # Can only create CIs during qanc_create_update
    return nil if @action != 'qanc_create_update'

    if !@enabled
      return _trace_disabled_state(message: 'ServiceNow ALM integration is DISABLED - skipping CI creation')
    end

    response = _query(
      action: @action,
      state: "update",
      snow_id: Context.pipeline.snow_change_id,
      ci_id: "#{Defaults.sections[:plan_key].upcase}-#{Defaults.sections[:branch]}-#{Defaults.sections[:build]}",
      payload: JSON.dump({
        "action" => "create_ci",
        "landscape_name" => "#{Defaults.sections[:plan_key].upcase}-#{Defaults.sections[:branch]}-#{Defaults.sections[:build]}",
        "landscape_component" => {
          "name" => "#{Defaults.sections[:plan_key].upcase}-#{Defaults.sections[:branch]}-#{Defaults.sections[:build]}-#{component_name}",
        },
      })
    )

    return response
  end

  # sets 'success' state for the giving action
  # @return [Hash] HTTP response payload as hash
  def done_success
    return nil if @action.nil? or !@enabled

    response = _query(
      action: @action,
      state: "success",
      snow_id: Context.pipeline.snow_change_id,
      payload: JSON.dump({
        "latest_build" => "#{Defaults.sections[:plan_key].upcase}-#{Defaults.sections[:branch]}-#{Defaults.sections[:build]}"
      }),
      ci_id: "#{Defaults.sections[:plan_key].upcase}-#{Defaults.sections[:branch]}-#{Defaults.sections[:build]}"
    )

    @action = nil
    return response
  end

  # sets 'failed' state for the giving action
  # @return [Hash] HTTP response payload as hash
  def done_failure
    return nil if @action.nil? or !@enabled

    response = _query(
      action: @action,
      state: "failed",
      snow_id: Context.pipeline.snow_change_id,
      ci_id: "#{Defaults.sections[:plan_key].upcase}-#{Defaults.sections[:branch]}-#{Defaults.sections[:build]}"
    )

    @action = nil
    return response
  end

  # sets 'new' state for the giving action
  # @param action [String] action name
  # @return [Hash] HTTP response payload as hash
  def _request_action(action)
    @action = action

    response = _query(
      action: @action,
      state: "new",
      snow_id: Context.pipeline.snow_release_id,
      ci_id: "#{Defaults.sections[:plan_key].upcase}-#{Defaults.sections[:branch]}-#{Defaults.sections[:build]}"
    )

    Log.info "ServiceNow request to perform action #{@action.inspect} returned: #{response.code} - #{response.message}"

    if response.code == "OK"
      payload = JSON.load(response.payload)
      Context.pipeline.snow_change_id = payload['changeID'] if payload.has_key? 'changeID'
      Context.pipeline.snow_release_id = payload['releaseID'] if payload.has_key? 'releaseID'
    end

    return response
  end

  # executes SNOW query using Savon
  # @param action [String] action name
  # @param application_message [String] application message
  # @param retry_options [Hash] retry options for retry service
  # @return an instance of Savon.call() response
  def _query(
    action: nil,
    state: nil,
    payload: nil,
    snow_id: nil,
    ci_id: nil
  )

    application_message = {
      'state' => state,
      'qda_id' => Defaults.sections[:qda].upcase,
      'as_id' => Defaults.sections[:as].upcase,
      'ase' => Defaults.sections[:ase].upcase,
    }
    application_message['payload'] = payload unless payload.nil?
    application_message['snow_id'] = snow_id unless snow_id.nil?
    application_message['ci_id'] = ci_id if !ci_id.nil? and action =~ /teardown|release/
    application_message['build_user'] = @build_user unless @build_user.nil?

    Log.debug("Calling ServiceNow action #{action.inspect} with message #{application_message.inspect}")
    response = _execute(action, application_message)
    Log.debug "ServiceNow response code: #{response.code.inspect}"
    Log.debug "ServiceNow response payload: #{response.payload.inspect}"
    Log.debug "ServiceNow response message: #{response.message.inspect}"

    return response
  end

  # safely executes SNOW query using Savon
  # @param action [String] action name
  # @param application_message [String] application message
  # @param retry_options [Hash] retry options for retry service
  # @return an instance of Savon.call() response
  def _execute_safe(action:, application_message:, retry_options:)
    require 'savon'

    # execute the ServiceNow call with safe reexecution
    # aiming to handle timeout errors cause by intermittent network connection loss
    # https://jira.qantas.com.au/browse/QCPFB-189
    _retry_service.exec_with_retry(options: retry_options) {
      wsdl = "#{@endpoint}/#{action}.do?WSDL"

      Log.debug "Executing SNOW call: #{wsdl}"

      client_options = {
        wsdl: wsdl,
        basic_auth: [@username, @password],
        open_timeout: 15,
        read_timeout: 15,
        log: false,
        log_level: :debug,
      }

      client_options[:proxy] = @proxy unless @proxy.nil?
      client = Savon.client(client_options)

      call_result = client.call(:execute, :message => application_message)

      next call_result
    }
  end

  def _execute(action, application_message)
    begin
      result = _execute_safe(
        action: action,
        application_message: application_message,
        retry_options: _snow_retry_options
      )

      response = result[:result_value]
    rescue => e
      msg = "Failed to execute ServiceNow query - #{e}"

      Log.error msg
      raise msg
    end

    response_body = response.body[:execute_response] || {}
    code    = response_body[:response] || ""
    payload = response_body[:payload]  || "{}"
    message = response_body[:message]  || ""

    return ServiceNowResponse.new(code, payload, message)
  end

  private

  # traces messages for disabled state
  # @return nil
  def _trace_disabled_state(message:)
    Log.warn   message
    Log.output message

    return nil
  end

  # returns default settings for the retry service
  # @return [Hash] hash with retry settings
  def _snow_retry_options
    # allow retry for exceptions which have the following values
    # the aim is to cover network issues
    # https://jira.qantas.com.au/browse/QCPFB-189
    {
      # retry 10 times within 10-18 seconds
      # gives 120-180 seconds at max before the final failure
      :retry_limit => 10,
      :retry_delay_range => [12, 18],

      :allowed_exception_messages => [
        # from the ticket itself
        /execution expired/,
        # 504 errors
        /Timeout/,
        /timeout/,
        # 503 errors
        /Service Unavailable/,
        /service unavailable/,
        # Operation timed out
        /Operation timed out/
      ]
    }
  end

  # Retry service used by other helpers to implement try-retry over non-retryable methods
  # it's lazy-load, will be initialied at first request to avoid static initializations with mixins
  # @return [RetryableService] an instance of RetryableService class
  def _retry_service
    if @retry_service.nil?
      @retry_service = ServiceContainer.instance.get_service(RetryableService)
    end

    @retry_service
  end
end
