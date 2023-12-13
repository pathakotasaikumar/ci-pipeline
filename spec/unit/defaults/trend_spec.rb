require 'defaults/trend'

RSpec.describe Defaults::Trend do
  context 'trend_dsm_url' do
    it 'successfully return trend dsm url' do
      allow(Context).to receive_message_chain('environment.variable').with('trend_dsm_url', nil).and_return('dummy-dsm-url')
      expect(Defaults.trend_dsm_url).to eq('dummy-dsm-url')
    end

    it 'fails to return trend_dsm_url key' do
      allow(Context).to receive_message_chain('environment.variable').with('trend_dsm_url', nil).and_return(nil)
      expect(Defaults.trend_dsm_url).to eq(nil)
    end
  end

  context 'trend_dsm_tenant_id' do
    it 'successfully return trend dsm tenant id' do
      allow(Context).to receive_message_chain('environment.variable').with('trend_dsm_tenant_id', nil).and_return('dummy-dsm-tenant-id')
      expect(Defaults.trend_dsm_tenant_id).to eq('dummy-dsm-tenant-id')
    end

    it 'fails to return trend_dsm_tenant_id key' do
      allow(Context).to receive_message_chain('environment.variable').with('trend_dsm_tenant_id', nil).and_return(nil)
      expect(Defaults.trend_dsm_tenant_id).to eq(nil)
    end
  end

  context 'trend_dsm_token' do
    it 'successfully return trend dsm token' do
      allow(Context).to receive_message_chain('environment.variable').with('trend_dsm_token', nil).and_return('dummy-dsm-token')
      expect(Defaults.trend_dsm_token).to eq('dummy-dsm-token')
    end

    it 'fails to return trend_dsm_token key' do
      allow(Context).to receive_message_chain('environment.variable').with('trend_dsm_token', nil).and_return(nil)
      expect(Defaults.trend_dsm_token).to eq(nil)
    end
  end

  context 'trend_dsm_saas_proxy' do
    it 'successfully return trend dsm saas proxy' do
      allow(Context).to receive_message_chain('environment.variable').with('trend_dsm_saas_proxy', nil).and_return('dummy-dsm-saas-proxy')
      expect(Defaults.trend_dsm_saas_proxy).to eq('dummy-dsm-saas-proxy')
    end

    it 'fails to return trend_dsm_saas_proxy key' do
      allow(Context).to receive_message_chain('environment.variable').with('trend_dsm_saas_proxy', nil).and_return(nil)
      expect(Defaults.trend_dsm_saas_proxy).to eq(nil)
    end
  end

  context 'trend_agent_activation_url' do
    it 'successfully return trend agent activation url' do
      allow(Context).to receive_message_chain('environment.variable').with('trend_agent_activation_url', nil).and_return('dummy-trend-agent-activation-url')
      expect(Defaults.trend_agent_activation_url).to eq('dummy-trend-agent-activation-url')
    end

    it 'fails to return trend_agent_activation_url key' do
      allow(Context).to receive_message_chain('environment.variable').with('trend_agent_activation_url', nil).and_return(nil)
      expect(Defaults.trend_agent_activation_url).to eq(nil)
    end
  end
end
