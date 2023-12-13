require 'defaults/snow'

RSpec.describe Defaults::Snow do
  context 'snow_enabled' do
    it 'return snow_enabled as False and skip_alm = true and environment = prod' do
      allow(Defaults).to receive(:sections).and_return({ :env => 'prod' })
      allow(Context).to receive_message_chain('environment.variable').with('skip_alm', 'false').and_return('true')
      expect(Defaults.snow_enabled).to eq(false)
    end

    it 'return snow_enabled as True and skip_alm = false and environment = prod' do
      allow(Defaults).to receive(:sections).and_return({ :env => 'prod' })
      allow(Context).to receive_message_chain('environment.variable').with('skip_alm', 'false').and_return('false')
      expect(Defaults.snow_enabled).to eq(true)
    end

    it 'return snow_enabled as false and skip_alm = nil and environment = nonp' do
      allow(Defaults).to receive(:sections).and_return({ :env => 'nonp' })
      allow(Context).to receive_message_chain('environment.variable').with('skip_alm', 'true').and_return('true')
      expect(Defaults.snow_enabled).to eq(false)
    end

    it 'return snow_enabled as true and skip_alm = false and environment = nonp' do
      allow(Defaults).to receive(:sections).and_return({ :env => 'nonp' })
      allow(Context).to receive_message_chain('environment.variable').with('skip_alm', 'true').and_return('false')
      expect(Defaults.snow_enabled).to eq(true)
    end
  end

  context 'snow_endpoint' do
    it 'returns snow_endpoint as false when no value' do
      allow(Context).to receive_message_chain('environment.variable').with('snow_endpoint', nil).and_return('http://dummy-url')
      expect(Defaults.snow_endpoint).to eq('http://dummy-url')
    end

    it 'returns nil snow_endpoint as false when no value' do
      allow(Context).to receive_message_chain('environment.variable').with('snow_endpoint', nil).and_return(nil)
      expect(Defaults.snow_endpoint).to eq(nil)
    end
  end

  context 'snow_user' do
    it 'returns snow_user as false when no value' do
      allow(Context).to receive_message_chain('environment.variable').with('snow_user', nil).and_return('dummy-user')
      expect(Defaults.snow_user).to eq('dummy-user')
    end

    it 'returns nil snow_user as false when no value' do
      allow(Context).to receive_message_chain('environment.variable').with('snow_user', nil).and_return(nil)
      expect(Defaults.snow_user).to eq(nil)
    end
  end

  context 'snow_password' do
    it 'returns snow_password as false when no value' do
      allow(Context).to receive_message_chain('environment.variable').with('snow_password', nil).and_return('dummy-password')
      expect(Defaults.snow_password).to eq('dummy-password')
    end

    it 'returns nil snow_user as false when no value' do
      allow(Context).to receive_message_chain('environment.variable').with('snow_password', nil).and_return(nil)
      expect(Defaults.snow_password).to eq(nil)
    end
  end
end
