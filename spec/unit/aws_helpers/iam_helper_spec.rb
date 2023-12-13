$LOAD_PATH.unshift("#{BASE_DIR}/lib/aws_helpers")
require 'iam_helper'

describe 'IamHelper' do
  context '_iam_helper_init' do
    it 'successful execution' do
      expect { AwsHelper._iam_helper_init }.not_to raise_exception
    end
  end

  context 'iam_get_policy' do
    it 'successful execution' do
      dummy_client = double(Aws::IAM::Client)
      allow(AwsHelper).to receive(:_iam_client).and_return(dummy_client)
      allow(dummy_client).to receive(:get_policy)
      expect {
        AwsHelper.iam_get_policy(policy_arn: 'dummy_policy_arn')
      }.not_to raise_exception
    end

    it 'fails - Failed to retrieve IAM Managed Policy ' do
      dummy_client = double(Aws::IAM::Client)
      allow(AwsHelper).to receive(:_iam_client).and_return(dummy_client)
      allow(dummy_client).to receive(:get_policy).and_raise(StandardError)
      expect(Log).to receive(:warn).and_return /Failed to retrieve IAM Managed Policy/
      expect {
        AwsHelper.iam_get_policy(policy_arn: 'dummy_policy_arn')
      }.not_to raise_exception
    end
  end

  context '_iam_client' do
    it 'successful execution - initialize no provisioning or control credentials' do
      allow(Aws::IAM::Client).to receive(:new)
      allow(AwsHelper).to receive(:_provisioning_credentials)
      allow(AwsHelper).to receive(:_control_credentials)
      expect { AwsHelper._iam_client }.not_to raise_exception
    end

    it 'successful execution - initialize with provisioning credentials' do
      allow(Aws::IAM::Client).to receive(:new)
      mock_credentials = double(Object)
      allow(AwsHelper).to receive(:_provisioning_credentials).and_return(mock_credentials)
      allow(AwsHelper).to receive(:_control_credentials)
      expect { AwsHelper._iam_client }.not_to raise_exception
    end

    it 'successful execution - initialize with control credentials' do
      allow(Aws::IAM::Client).to receive(:new)
      mock_credentials = double(Object)
      allow(AwsHelper).to receive(:_provisioning_credentials)
      allow(AwsHelper).to receive(:_control_credentials).and_return(mock_credentials)
      expect { AwsHelper._iam_client }.not_to raise_exception
    end
  end
end
