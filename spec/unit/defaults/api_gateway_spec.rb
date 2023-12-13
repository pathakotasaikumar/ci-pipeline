require 'defaults/api_gateway'

RSpec.describe Defaults::ApiGateway do
  context 'api_gateway_username' do
    it 'successfully return Api Gateway registration username' do
      allow(Context).to receive_message_chain('environment.variable').with('api_gateway_username', nil).and_return('dummy-user')
      expect(Defaults.api_gateway_username).to eq('dummy-user')
    end

    it 'returns nil' do
      allow(Context).to receive_message_chain('environment.variable').with('api_gateway_username', nil).and_return(nil)
      expect(Defaults.api_gateway_username).to eq(nil)
    end
  end

  context 'api_gateway_password' do
    it 'successfully returns api_gateway_password' do
      allow(Context).to receive_message_chain('environment.variable').with('api_gateway_password', nil).and_return('dummy-password')
      expect(Defaults.api_gateway_password).to eq('dummy-password')
    end

    it 'returns nil' do
      allow(Context).to receive_message_chain('environment.variable').with('api_gateway_password', nil).and_return(nil)
      expect(Defaults.api_gateway_password).to eq(nil)
    end
  end

  context 'api_gateway_admin_url' do
    it 'successfully returns api_gateway_admin_url for prod' do
      allow(Defaults).to receive(:sections).and_return(env: 'prod')
      allow(Context).to receive_message_chain('environment.variable').with('api_gateway_admin_url_prod', nil).and_return('http://dummy-prod-url')
      expect(Defaults.api_gateway_admin_url).to eq('http://dummy-prod-url')
    end

    it 'successfully returns api_gateway_admin_url for prod' do
      allow(Defaults).to receive(:sections).and_return(env: 'nonp')
      allow(Context).to receive_message_chain('environment.variable').with('api_gateway_admin_url_nonp', nil).and_return('http://dummy-nonp-url')
      expect(Defaults.api_gateway_admin_url).to eq('http://dummy-nonp-url')
    end
  end

  context 'api_gateway_cross_account_role_arn' do
    it 'successfully returns api_gateway_cross_account_role_arn for prod' do
      allow(Defaults).to receive(:sections).and_return(env: 'prod')
      allow(Context).to receive_message_chain('environment.variable').with('api_gateway_cross_account_role_arn_prod', nil).and_return('dummy-prod-arn')
      expect(Defaults.api_gateway_cross_account_role_arn).to eq('dummy-prod-arn')
    end

    it 'successfully returns api_gateway_cross_account_role_arn for nonprod' do
      allow(Defaults).to receive(:sections).and_return(env: 'nonp')
      allow(Context).to receive_message_chain('environment.variable').with('api_gateway_cross_account_role_arn_nonp', nil).and_return('dummy-nonp-arn')
      expect(Defaults.api_gateway_cross_account_role_arn).to eq('dummy-nonp-arn')
    end
  end

  context 'api_gateway_registration_key' do
    it 'successfully returns api_gateway_admin_url for prod' do
      allow(Context).to receive_message_chain('environment.variable').and_return('AMS01-C031S01DEV_MASTER')
      allow(Defaults).to receive(:sections).and_return(
        plan_key: 'ams01-c031s01dev',
        branch: 'feature/123'
      )
      expect(Defaults.api_gateway_registration_key).to eq('AMS01-C031S01DEV_MASTER')
    end

    it 'api_key_master' do
      allow(Defaults).to receive(:sections).and_return(
        plan_key: 'ams99-a914s01prod',
        branch: 'master'
      )

      expect(Defaults.api_gateway_registration_key).to eq('AMS99-A914S01PROD_MASTER')
    end

    it 'api_key_feature_branch' do
      allow(Defaults).to receive(:sections).and_return(
        plan_key: 'ams99-a914s01dev',
        branch: 'feature/1234'
      )

      expect(Defaults.api_gateway_registration_key).to eq('AMS99-A914S01DEV_FEATURE-1234')
    end
  end
end
