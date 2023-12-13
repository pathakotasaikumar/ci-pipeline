require 'defaults/backup'

RSpec.describe Defaults::Environment do
  context 'provisioning_role_name' do
    it 'successfully return default value' do
      expect(Defaults.provisioning_role_name).to eq('qcp-platform-provision')
    end
  end

  context 'provisioning_role' do
    it 'successfully return nil' do
      allow(Defaults).to receive(:account_id) .and_return(nil)
      allow(Defaults).to receive(:provisioning_role_name) .and_return(nil)
      expect(Defaults.provisioning_role).to eq(nil)

      allow(Defaults).to receive(:account_id) .and_return('account-1')
      allow(Defaults).to receive(:provisioning_role_name) .and_return(nil)

      expect(Defaults.provisioning_role).to eq(nil)
    end

    it 'successfully returns value' do
      account_id = 'account-1'
      provisioning_role_name = 'role-name-1'

      allow(Defaults).to receive(:account_id) .and_return(account_id)
      allow(Defaults).to receive(:provisioning_role_name) .and_return(provisioning_role_name)

      expect(Defaults.provisioning_role).to eq("arn:aws:iam::#{account_id}:role/#{provisioning_role_name}")
    end
  end
end
