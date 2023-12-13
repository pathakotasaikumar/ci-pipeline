require 'defaults/splunk'

RSpec.describe Defaults::Splunk do
  context 'splunk_url' do
    it 'successfully return splunk URL' do
      allow(Context).to receive_message_chain('environment.variable').with('splunk_url', nil).and_return('http://dummy-url')
      expect(Defaults.splunk_url).to eq('http://dummy-url')
    end

    it 'fails to return splunk URL' do
      allow(Context).to receive_message_chain('environment.variable').with('splunk_url', nil).and_return(nil)
      expect(Defaults.splunk_url).to eq(nil)
    end
  end

  context 'splunk_token_password' do
    it 'successfully returns splunk token' do
      allow(Context).to receive_message_chain('environment.variable').with('splunk_token_password', nil).and_return('dummy-password')
      expect(Defaults.splunk_token_password).to eq('dummy-password')
    end

    it 'fails to return splunk password' do
      allow(Context).to receive_message_chain('environment.variable').with('splunk_token_password', nil).and_return(nil)
      expect(Defaults.splunk_token_password).to eq(nil)
    end
  end
end
