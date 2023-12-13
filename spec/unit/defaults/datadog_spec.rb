require 'defaults/datadog'

RSpec.describe Defaults::Datadog do
  context 'datadog_api_keys' do
    it 'successfully return datadog_api_keys api key' do
      allow(Context).to receive_message_chain('environment.variable').with('datadog_api_keys', nil).and_return('dummy-datadog-api-key')
      expect(Defaults.datadog_api_keys).to eq('dummy-datadog-api-key')
    end

    it 'fails to return datadog_api_keys key' do
      allow(Context).to receive_message_chain('environment.variable').with('datadog_api_keys', nil).and_return(nil)
      expect(Defaults.datadog_api_keys).to eq(nil)
    end
  end
end
