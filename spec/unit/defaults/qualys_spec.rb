require 'defaults/qualys'

RSpec.describe Defaults::Qualys do
  context 'qualys_activation_id' do
    it 'successfully return qualys_activation_id api key' do
      allow(Context).to receive_message_chain('environment.variable').with('qualys_activation_id', nil).and_return('dummy-qualys-key')
      expect(Defaults.qualys_activation_id).to eq('dummy-qualys-key')
    end

    it 'fails to return qualys_activation_id key' do
      allow(Context).to receive_message_chain('environment.variable').with('qualys_activation_id', nil).and_return(nil)
      expect(Defaults.qualys_activation_id).to eq(nil)
    end
  end
  context 'aqos_release_dns' do
    it 'successfully return aqos_release_dns ' do
      allow(Context).to receive_message_chain('environment.variable').with('aqos_release_dns', nil).and_return('dummy-aqos_release_dns')
      expect(Defaults.aqos_release_dns).to eq('dummy-aqos_release_dns')
    end

    it 'fails to return aqos_release_dns ' do
      allow(Context).to receive_message_chain('environment.variable').with('aqos_release_dns', nil).and_return(nil)
      expect(Defaults.aqos_release_dns).to eq(nil)
    end
  end
end
