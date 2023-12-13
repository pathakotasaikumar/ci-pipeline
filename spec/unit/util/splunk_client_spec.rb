require "#{BASE_DIR}/lib/util/splunk_client.rb"

RSpec.describe 'SplunkClient' do
  before(:context) do
    @splunk_url = ENV['bamboo_splunk_url']
    @splunk_token = ENV['bamboo_splunk_token_password']

    @splunk_url_test = 'http://splunk-test.local'
    @splunk_token_test = '123'

    if @splunk_url.to_s.empty? || @splunk_token.to_s.empty?
      _log_splunk_unavailable
    else

      @payload = {
        is_debug: true,
        branch: 'branch_name_' + rand(1000).to_s,
        branch_name: 'name_' + rand(1000).to_s,
        branch_id: 'id_' + rand(1000).to_s,
        branches: {
          sub_value_1: rand(1000).to_s,
          sub_value_2: rand(1000)
        }
      }

      @splunk_client = SplunkClient.new(url: @splunk_url, token: @splunk_token)

    end
  end

  context '.send_data_async' do
    it 'does not raise exceptions' do
      client = SplunkClient.new(url: @splunk_url_test, token: @splunk_token_test)
      client.send_data_async({})
    end
  end

  context '.send_data' do
    it 'returns false on invalid responce' do
      client = SplunkClient.new(url: @splunk_url_test, token: @splunk_token_test)

      http_client_mock = double(Net::HTTP)
      client.instance_variable_set(:@http_client, http_client_mock)

      allow(http_client_mock).to receive(:request)
      expect(client.send_data({})).to eq(false)
    end

    it 'returns true on valid responce' do
      client = SplunkClient.new(url: @splunk_url_test, token: @splunk_token_test)

      http_client_mock = double(Net::HTTP)
      http_responce_mock = double(Net::HTTPResponse)

      client.instance_variable_set(:@http_client, http_client_mock)

      allow(http_client_mock).to receive(:request) .and_return(http_responce_mock)
      allow(http_client_mock).to receive(:_prepare_payload) .and_return("")

      allow(http_responce_mock).to receive(:code) .and_return(200)
      allow(http_responce_mock).to receive(:is_a?) .and_return(true)
      allow(http_responce_mock).to receive(:body) .and_return('{"text": "Success"}')

      expect(client.send_data({})).to eq(true)
    end

    it 'returns false on invalid responce' do
      client = SplunkClient.new(url: @splunk_url_test, token: @splunk_token_test)

      http_client_mock = double(Net::HTTP)
      http_responce_mock = double(Net::HTTPResponse)

      client.instance_variable_set(:@http_client, http_client_mock)

      allow(http_client_mock).to receive(:request) .and_return(http_responce_mock)
      allow(http_client_mock).to receive(:_prepare_payload) .and_return("")

      allow(http_responce_mock).to receive(:code) .and_return(200)
      allow(http_responce_mock).to receive(:is_a?) .and_return(true)
      allow(http_responce_mock).to receive(:body) .and_return('{"text": "Error"}')

      expect(client.send_data({})).to eq(false)
    end

    it 'returns false on non-HTTPResponse responce' do
      client = SplunkClient.new(url: @splunk_url_test, token: @splunk_token_test)

      http_client_mock = double(Net::HTTP)
      http_responce_mock = double(Net::HTTPResponse)

      client.instance_variable_set(:@http_client, http_client_mock)

      allow(http_client_mock).to receive(:request) .and_return(http_responce_mock)
      allow(http_client_mock).to receive(:_prepare_payload) .and_return("")

      allow(http_responce_mock).to receive(:code) .and_return(200)
      # allow(http_responce_mock).to receive(:is_a?) .and_return(true)
      allow(http_responce_mock).to receive(:body) .and_return('{"text": "Error"}')

      expect(client.send_data({})).to eq(false)
    end

    it 'raises exception on non-hash' do
      client = SplunkClient.new(url: @splunk_url_test, token: @splunk_token_test)

      # fail early with intentionally wrongly set URL to connect
      # send_data should not raise an exception, only log
      # setting http_connect_timeout as 1 sec speeds up unit tests, overwise it would stuck for 20-20 seconds
      client.http_connect_timeout = 1

      expect {
        client.send_data({})
      }.not_to raise_error

      expect {
        client.send_data("1")
      }.not_to raise_error

      expect {
        client.send_data(2)
      }.not_to raise_error
    end
  end

  context 'splunk_client' do
    it '._log' do
      client = SplunkClient.new(url: @splunk_url_test, token: @splunk_token_test)
      client.send(:_log, 'test')
    end

    it 'can_create_client' do
      SplunkClient.new(url: @splunk_url_test, token: @splunk_token_test)
    end

    it 'create_client_fail' do
      expect { SplunkClient.new(url: '', token: '') }
        .to raise_error('url is required')

      expect { SplunkClient.new(url: @splunk_url_test, token: '') }
        .to raise_error('token is required')
    end

    it 'splunk_client_create_fail' do
      expect {
        SplunkClient.new(url: @splunk_url_test, token: @splunk_token_test)
      }.not_to raise_error
    end

    it 'send_data_fail1' do
      splunk_client = double(SplunkClient)
      allow(splunk_client).to receive(:send_data).with(nil).and_raise(/has to be a Hash/)
    end

    it 'send_data_fail2' do
      splunk_client = double(SplunkClient)
      allow(splunk_client).to receive(:send_data).with('1').and_raise(/has to be a Hash/)
    end

    it 'send_data_fail3' do
      splunk_client = double(SplunkClient)
      allow(splunk_client).to receive(:send_data).with(1).and_raise(/has to be a Hash/)
    end

    it 'validate_response_fail1' do
      splunk_client = SplunkClient.new(
        url: 'http://dummy',
        token: 'dummy'
      )
      response = Net::HTTPResponse.new('1', '304', 'OK')
      expect(splunk_client.validate_response(response)).to eq false
    end

    it 'validate_response_fail2' do
      splunk_client = SplunkClient.new(
        url: 'http://dummy', token: 'dummy'
      )
      response = nil
      expect(splunk_client.validate_response(response)).to eq false
    end
  end

  context 'integration_tests' do
    it 'send_synchronous_nil' do
      if defined?(@splunk_client)
        expect(Log).to receive(:warn).with(/Data argument must be a Hash instance/)
        @splunk_client.send_data(nil)
      else
        _log_splunk_unavailable
      end
    end

    it 'send_synchronous_nil' do
      if defined?(@splunk_client)
        expect(Log).to receive(:warn).with(/Data argument must be a Hash instance/)
        @splunk_client.send_data([])
      else
        _log_splunk_unavailable
      end
    end

    it 'send_synchronous' do
      if defined?(@splunk_client)
        result = @splunk_client.send_data(@payload)
        expect(result).to eq true
      else
        _log_splunk_unavailable
      end
    end

    it 'send_asynchronous' do
      if defined?(@splunk_client)
        th = @splunk_client.send_data_async(@payload)
        th.join

        result = th[:output]
        expect(result).to eq true
      else
        _log_splunk_unavailable
      end
    end
  end

  private

  def _log_splunk_unavailable
    Log.warn 'Skipping Spunk integration test - splunk_url/splunk_token are empty.
         Set ENV["bamboo_splunk_url"]/ENV["bamboo_splunk_token_password"] variables'
  end
end
