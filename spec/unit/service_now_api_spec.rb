$LOAD_PATH.unshift("#{BASE_DIR}/lib")
require 'service_now_api'

RSpec.describe ServiceNowApi do
  def _get_api_client(enabled: true, request_action: nil)
    ServiceNowApi.new(
      endpoint: 'http://localhost.local',
      username: 'user',
      password: 'password',
      enabled: enabled,
      request_action: request_action
    )
  end

  describe '.initialize' do
    it 'can create new instance' do
      client = _get_api_client
      expect(client).not_to eq(nil)
    end

    it 'initializes retry service' do
      client = _get_api_client
      service = client.__send__(:_retry_service)

      expect(service).not_to be(nil)
    end

    it 'initializes retry options' do
      client = _get_api_client
      options = client.__send__(:_snow_retry_options)

      expect(options).to eq({
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
      })
    end
  end

  describe '.request_deploy' do
    it 'does nothing if disabled' do
      client = _get_api_client(enabled: false)

      expect(client.request_deploy).to eq(nil)
    end

    it 'returns value' do
      client = _get_api_client(enabled: true)
      response = double(Object)

      allow(response).to receive(:code) .and_return("OK")
      allow(client).to receive(:_request_action).with('qanc_create_update') .and_return(response)

      result = client.request_deploy

      expect(result).not_to eq(nil)
      expect(result.code).to eq("OK")
    end
  end

  describe '.request_release' do
    it 'does nothing if disabled' do
      client = _get_api_client(enabled: false)

      expect(client.request_release).to eq(nil)
    end

    it 'returns value' do
      client = _get_api_client(enabled: true)
      response = double(Object)

      allow(response).to receive(:code) .and_return("OK")
      allow(client).to receive(:_request_action).with('qanc_release') .and_return(response)

      result = client.request_release

      expect(result).not_to eq(nil)
      expect(result.code).to eq("OK")
    end
  end

  describe '.request_teardown' do
    it 'does nothing if disabled' do
      client = _get_api_client(enabled: false)

      expect(client.request_teardown).to eq(nil)
    end

    it 'returns value' do
      client = _get_api_client(enabled: true)
      response = double(Object)

      allow(response).to receive(:code) .and_return("OK")
      allow(client).to receive(:_request_action).with('qanc_teardown') .and_return(response)

      result = client.request_teardown

      expect(result).not_to eq(nil)
      expect(result.code).to eq("OK")
    end
  end

  describe '.log_message' do
    it 'does nothing if disabled' do
      client = _get_api_client(enabled: false)
      expect(client.log_message('message')).to eq(nil)
    end

    it 'logs data' do
      client = _get_api_client(enabled: true, request_action: 'log')
      response = { code: "OK" }

      allow(client).to receive(:_query) .and_return(response)

      expect(client.log_message('message')).to be(response)
    end
  end

  describe '.create_ci' do
    it 'does nothing on non-qanc_create_update action' do
      client = _get_api_client(enabled: false, request_action: 'log')
      expect(client.create_ci('my-component')).to eq(nil)
    end

    it 'does nothing on disabled qanc_create_update action' do
      client = _get_api_client(enabled: false, request_action: 'qanc_create_update')
      expect(client.create_ci('my-component')).to eq(nil)
    end

    it 'logs data' do
      client = _get_api_client(enabled: true, request_action: 'qanc_create_update')

      response = { code: "OK" }
      allow(client).to receive(:_query) .and_return(response)

      expect(client.create_ci('my-component')).to eq(response)
    end
  end

  describe '.done_success' do
    it 'does nothing on empty action' do
      client = _get_api_client(enabled: false)
      expect(client.done_success).to eq(nil)
    end

    it 'does nothing if disabled' do
      client = _get_api_client(enabled: false, request_action: 'test')
      expect(client.done_success).to eq(nil)
    end

    it 'logs data' do
      client = _get_api_client(enabled: true, request_action: 'test')

      response = { code: "OK" }
      allow(client).to receive(:_query) .and_return(response)

      expect(client.done_success).to eq(response)
    end
  end

  describe '.done_failure' do
    it 'does nothing on empty action' do
      client = _get_api_client(enabled: false)
      expect(client.done_failure).to eq(nil)
    end

    it 'does nothing if disabled' do
      client = _get_api_client(enabled: false, request_action: 'test')
      expect(client.done_failure).to eq(nil)
    end

    it 'logs data' do
      client = _get_api_client(enabled: true, request_action: 'test')

      response = { code: "OK" }
      allow(client).to receive(:_query) .and_return(response)

      expect(client.done_failure).to eq(response)
    end
  end

  describe '._request_action' do
    it 'saves snow_change_id/snow_release_id on success' do
      client = _get_api_client(enabled: true, request_action: 'test')
      response = double(Object)

      change_id = 1
      release_id = 2

      payload = "{ \"changeID\": #{change_id}, \"releaseID\": #{release_id} }"

      allow(response).to receive(:code) .and_return("OK")
      allow(response).to receive(:message) .and_return("message body")
      allow(response).to receive(:payload) .and_return(payload)

      allow(Context).to receive_message_chain('pipeline.snow_change_id=').with(change_id)
      allow(Context).to receive_message_chain('pipeline.snow_release_id=').with(release_id)

      allow(Context).to receive_message_chain('pipeline.snow_release_id')
      allow(client).to receive(:_query) .and_return(response)

      expect(client.send(:_request_action, 'test')).to eq(response)
    end
  end

  describe '._query' do
    it 'executes query' do
      action = 'test action'
      state = 'test state'

      application_message = {
        'state' => state,
        'qda_id' => Defaults.sections[:qda].upcase,
        'as_id' => Defaults.sections[:as].upcase,
        'ase' => Defaults.sections[:ase].upcase,
      }

      client = _get_api_client(enabled: true, request_action: 'test')
      response = double(Object)

      allow(response).to receive(:code)
      allow(response).to receive(:payload)
      allow(response).to receive(:message)

      allow(client).to receive(:_execute).with(action, application_message) .and_return(response)

      result = nil

      expect {
        result = client.__send__(
          :_query,
          action: action,
          state: state
        )
      }.not_to raise_error

      expect(result).to eq(response)
    end
  end

  describe '._execute' do
    it 'raises error on fail' do
      require 'savon'

      code = 'response 1'
      payload = 'payload 1'
      message = 'message 1'

      action = 'test action'
      application_message = 'test mesage'

      savon_client = double(Object)
      response = double(Object)
      response_hash = {
        :execute_response => {
          :response => code,
          :payload => payload,
          :message => message,
        }
      }

      allow(savon_client).to receive(:call) .and_raise('error while calling ServiceNow')
      allow(Savon).to receive(:client) .and_return(savon_client)

      allow(response).to receive(:body) .and_return(response_hash)

      client = _get_api_client(enabled: true, request_action: 'test')

      expect {
        result = client.__send__(:_execute, action, application_message)
      }.to raise_error(/Failed to execute ServiceNow query - error while calling ServiceNow/)
    end

    it 'executes query' do
      require 'savon'

      code = 'response 1'
      payload = 'payload 1'
      message = 'message 1'

      action = 'test action'
      application_message = 'test mesage'

      savon_client = double(Object)
      response = double(Object)
      response_hash = {
        :execute_response => {
          :response => code,
          :payload => payload,
          :message => message,
        }
      }

      allow(savon_client).to receive(:call) .and_return(response)
      allow(Savon).to receive(:client) .and_return(savon_client)

      allow(response).to receive(:body) .and_return(response_hash)

      client = _get_api_client(enabled: true, request_action: 'test')
      result = client.__send__(:_execute, action, application_message)

      expect(result.class).to eq(ServiceNowResponse)

      expect(result[:code]).to eq(code)
      expect(result[:payload]).to eq(payload)
      expect(result[:message]).to eq(message)
    end

    it 'executes retry query' do
      require 'savon'

      code = 'response 1'
      payload = 'payload 1'
      message = 'message 1'

      action = 'test action'
      application_message = 'test mesage'

      savon_client = double(Object)
      response = double(Object)
      response_hash = {
        :execute_response => {
          :response => code,
          :payload => payload,
          :message => message,
        }
      }

      try = 0

      allow(savon_client).to receive(:call) {
        try = try + 1

        if try < 2
          Log.warn "#{try} attempt, raising error"
          raise ('timeout')
        else
          Log.warn "#{try} attempt, continue execution"
        end
      }

      allow(Savon).to receive(:client) .and_return(savon_client)
      allow(response).to receive(:body) .and_return(response_hash)

      client = _get_api_client(enabled: true, request_action: 'test')

      retry_options = client.__send__(:_snow_retry_options)

      retry_options[:retry_limit] = 3
      retry_options[:retry_delay_range] = [0, 1]

      result = client.__send__(
        :_execute_safe,
        action: action,
        application_message: application_message,
        retry_options: retry_options
      )

      # expect result structure
      # it should try twice, fails once and execute well second time
      expect(result[:result_try]).to eq(2)

      expect(result[:attempts][0][:exception].message).to eq('timeout')
      expect(result[:attempts][1][:success]).to eq(true)
    end
  end
end
