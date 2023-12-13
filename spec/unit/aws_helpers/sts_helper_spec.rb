$LOAD_PATH.unshift("#{BASE_DIR}/lib/aws_helpers")
require 'sts_helper'

describe 'StsHelper' do
  context '_sts_helper_init' do
    it 'successful execution' do
      expect { AwsHelper._sts_helper_init }.not_to raise_exception
    end
  end

  context 'sts_get_role_credentials' do
    it 'successful execution - :auto' do
      allow(AwsHelper).to receive(:_sts_control_client)
      allow(AwsHelper).to receive(:_sts_base_client)
      allow(Defaults).to receive(:sections).and_return(
        qda: 'C031',
        env: 'NONP',
        as: '01'
      )
      allow(Aws::AssumeRoleCredentials).to receive(:new)
      expect {
        AwsHelper.sts_get_role_credentials('dummy-role-arn', :auto)
      }.not_to raise_exception
    end

    it 'successful execution - :control' do
      allow(AwsHelper).to receive(:_sts_control_client)
      allow(AwsHelper).to receive(:_sts_base_client)
      allow(Defaults).to receive(:sections).and_return(
        qda: 'C031',
        env: 'NONP',
        as: '01'
      )
      allow(Aws::AssumeRoleCredentials).to receive(:new)
      expect {
        AwsHelper.sts_get_role_credentials('dummy-role-arn', :control)
      }.not_to raise_exception
    end

    it 'successful execution - default' do
      allow(AwsHelper).to receive(:_sts_control_client)
      allow(AwsHelper).to receive(:_sts_base_client)
      allow(Defaults).to receive(:sections).and_return(
        qda: 'C031',
        env: 'NONP',
        as: '01'
      )
      allow(Aws::AssumeRoleCredentials).to receive(:new)
      expect {
        AwsHelper.sts_get_role_credentials('dummy-role-arn', 'dummy-client')
      }.not_to raise_exception
    end
  end

  context '_control_credentials' do
    it 'successful execution - initialize no provisioning or control credentials' do
      allow(Aws::STS::Client).to receive(:new)
      AwsHelper.instance_variable_set(:@sts_control_role, 'dummy-control-role')
      allow(AwsHelper).to receive(:sts_get_role_credentials)
      expect { AwsHelper._control_credentials }.not_to raise_exception
    end
  end

  context '_provisioning_credentials' do
    it 'successful execution - initialize no provisioning or control credentials' do
      allow(Aws::STS::Client).to receive(:new)
      AwsHelper.instance_variable_set(:@sts_provisioning_role, 'dummy-provisioning-role')
      allow(AwsHelper).to receive(:sts_get_role_credentials)
      expect { AwsHelper._provisioning_credentials }.not_to raise_exception
    end
  end

  context '_sts_base_client' do
    it 'successful execution - initialize no provisioning or control credentials' do
      allow(Aws::STS::Client).to receive(:new)
      allow(AwsHelper).to receive(:_control_credentials)
      expect { AwsHelper._sts_base_client }.not_to raise_exception
    end
  end

  context '_sts_control_client' do
    it 'successful execution - initialize no provisioning or control credentials' do
      allow(Aws::STS::Client).to receive(:new)
      allow(AwsHelper).to receive(:_control_credentials)
      expect { AwsHelper._sts_control_client }.not_to raise_exception
    end
  end
end
