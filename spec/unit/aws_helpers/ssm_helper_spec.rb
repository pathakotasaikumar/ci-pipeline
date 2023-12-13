$LOAD_PATH.unshift("#{BASE_DIR}/lib/aws_helpers")
require 'ssm_helper'

describe 'Ssm' do
  context 'ssm_client' do
    it 'initialize without error' do
      allow(Aws::SSM::Client).to receive(:new)
      allow(AwsHelper).to receive(:_provisioning_credentials)
      allow(AwsHelper).to receive(:_control_credentials)
      expect { AwsHelper._ssm_client }.not_to raise_exception
    end

    it 'initialize without error' do
      allow(Aws::SSM::Client).to receive(:new)
      allow(AwsHelper).to receive(:_provisioning_credentials)
      expect { AwsHelper._ssm_provision_client }.not_to raise_exception
    end
  end

  context 'ssm_get_parameter' do
    it 'successfully executes' do
      dummy_client = double(Aws::SSM::Client)
      parameters = double(Object)
      allow(AwsHelper).to receive(:_ssm_client).and_return(dummy_client)
      allow(dummy_client).to receive(:get_parameters).and_return(parameters)
      allow(parameters).to receive(:empty?)
      allow(parameters).to receive_message_chain('parameters.first.value').and_return('dummy-param-value')
      expect(
        AwsHelper.ssm_get_parameter(
          name: 'dummy-parameter-name'
        )
      ).to eq('dummy-param-value')
    end

    it 'successfully executes' do
      dummy_client = double(Aws::SSM::Client)
      allow(AwsHelper).to receive(:_ssm_client).and_return(dummy_client)
      allow(dummy_client).to receive(:get_parameters).and_raise StandardError
      expect {
        AwsHelper.ssm_get_parameter(
          name: 'dummy-parameter-name'
        )
      }.to raise_exception StandardError
    end
  end

  context 'ssm_get_parameters_by_path' do
    it 'successfully executes' do
      dummy_client = double(Aws::SSM::Client)
      parameters = double(Object)
      allow(AwsHelper).to receive(:_ssm_client).and_return(dummy_client)
      allow(dummy_client).to receive(:get_parameters_by_path).and_return(parameters)
      allow(parameters).to receive(:empty?).and_return(false)
      allow(parameters).to receive(:parameters).and_return(['param1', 'param2'])
      allow(parameters).to receive(:next_token).and_return(nil)
      expect(
        AwsHelper.ssm_get_parameters_by_path(
          path: 'dummy-parameter-name',
          recursive: true
        )
      ).to eq(['param1', 'param2'])
    end

    it 'successfully executes testing with provision client' do
      dummy_client = double(Aws::SSM::Client)
      parameters = double(Object)
      allow(AwsHelper).to receive(:_ssm_provision_client).and_return(dummy_client)
      allow(dummy_client).to receive(:get_parameters_by_path).and_return(parameters)
      allow(parameters).to receive(:empty?).and_return(false)
      allow(parameters).to receive(:parameters).and_return(['param1', 'param2'])
      allow(parameters).to receive(:next_token).and_return(nil)
      expect(
        AwsHelper.ssm_get_parameters_by_path(
          path: 'dummy-parameter-name',
          recursive: true,
          assume_provision_client: true
        )
      ).to eq(['param1', 'param2'])
    end
  end
end
