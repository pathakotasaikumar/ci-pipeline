require 'defaults/longlived'

RSpec.describe Defaults::Longlived do
  context 'puppet_server' do
    it 'successfully return puppet_server api key' do
      allow(Context).to receive_message_chain('environment.variable').with('lri_puppet_server', nil).and_return('dummy-puppet-server')
      expect(Defaults.puppet_server).to eq('dummy-puppet-server')
    end
  end

  context 'qcp_lri_nonproduction' do
    it 'successfully return puppet_server api key' do
      allow(Context).to receive_message_chain('environment.variable').with('lri_puppet_qcp_lri_nonproduction', 'qcp_lri_nonproduction').and_return('dummy-puppet_qcp_lri_nonproduction')
      expect(Defaults.puppet_qcp_lri_nonproduction).to eq('dummy-puppet_qcp_lri_nonproduction')
    end
  end

  context 'puppet_qcp_lri_production' do
    it 'successfully return puppet_server api key' do
      allow(Context).to receive_message_chain('environment.variable').with('lri_puppet_qcp_lri_production', 'qcp_lri_production').and_return('dummy-puppet_qcp_lri_production')
      expect(Defaults.puppet_qcp_lri_production).to eq('dummy-puppet_qcp_lri_production')
    end
  end

  context 'windows_patchgroup' do
    it 'successfully return puppet_server api key' do
      allow(Context).to receive_message_chain('environment.variable').with('windows_patchgroup', 'windows-core-baseline').and_return('dummy-windows_patchgroup')
      expect(Defaults.windows_patchgroup).to eq('dummy-windows_patchgroup')
    end
  end

  context 'centos_patchgroup' do
    it 'successfully return puppet_server api key' do
      allow(Context).to receive_message_chain('environment.variable').with('centos_patchgroup', 'centos-core-baseline').and_return('dummy-centos_patchgroup')
      expect(Defaults.centos_patchgroup).to eq('dummy-centos_patchgroup')
    end
  end

  context 'rhel_patchgroup' do
    it 'successfully return puppet_server api key' do
      allow(Context).to receive_message_chain('environment.variable').with('rhel_patchgroup', 'rhel-core-baseline').and_return('dummy-rhel_patchgroup')
      expect(Defaults.rhel_patchgroup).to eq('dummy-rhel_patchgroup')
    end
  end
end
