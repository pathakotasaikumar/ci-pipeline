$LOAD_PATH.unshift("#{BASE_DIR}/lib/aws_helpers")
require 'amq_broker_helper'

describe 'AmqBrokerHelper' do
  context '_amq_client' do
    it 'should create amq client - initialize no provisioning or control credentials' do
      allow(Aws::MQ::Client).to receive(:new)
      allow(AwsHelper).to receive(:_provisioning_credentials)
      expect { AwsHelper._amq_client }.not_to raise_exception
    end

    it 'successful execution - initialize with control credentials' do
      allow(Aws::MQ::Client).to receive(:new)
      mock_credentials = double(Object)
      allow(AwsHelper).to receive(:_provisioning_credentials).and_return(mock_credentials)
      expect { AwsHelper._amq_client }.not_to raise_exception
    end
  end

  context 'list_amq_tags' do
    it 'lists tags applied on the resources' do
      dummy_client = double(Aws::MQ::Client)
      mock_response = double(Object)
      allow(AwsHelper).to receive(:_amq_client).and_return(dummy_client)
      allow(dummy_client).to receive(:list_tags).and_return(mock_response)
      allow(mock_response).to receive(:tags).and_return(nil)
      allow(AwsHelper).to receive(:sts_get_role_credentials)
      expect do
        AwsHelper.list_amq_tags(
          resource_arn: 'test-arn'
        )
      end.not_to raise_exception
    end
  end

  context 'create_amq_tag' do
    it 'should tag amq if tags does not exist' do
      dummy_client = double(Aws::MQ::Client)
      mock_response = double(Object)
      allow(AwsHelper).to receive(:_amq_client).and_return(dummy_client)
      allow(AwsHelper).to receive(:sts_get_role_credentials)
      allow(dummy_client).to receive(:list_tags).and_return(mock_response)
      allow(mock_response).to receive(:tags).and_return(nil)
      allow(dummy_client).to receive(:create_tags).with(resource_arn: 'test-arn',
                                                        tags: { 'QDAID' => 'C031' }).and_return(nil)

      expect do
        AwsHelper.apply_amq_tags(
          resource_arn: 'test-arn',
          tags: {
            'QDAID' => 'C031'
          }
        )
      end.not_to raise_exception
    end

    it 'should tag amq' do
      dummy_client = double(Aws::MQ::Client)
      mock_response = double(Object)
      allow(AwsHelper).to receive(:_amq_client).and_return(dummy_client)
      allow(AwsHelper).to receive(:sts_get_role_credentials)
      allow(dummy_client).to receive(:list_tags).and_return(mock_response)
      allow(mock_response).to receive(:tags).and_return({ 'QDAID' => 'C031' })
      allow(dummy_client).to receive(:create_tags).with(resource_arn: 'test-arn',
                                                        tags: { 'QDAID' => 'C031' }).and_return(tags: { 'QDAID' => 'C031' })

      expect do
        AwsHelper.apply_amq_tags(
          resource_arn: 'test-arn',
          tags: {
            'QDAID' => 'C031'
          }
        )
      end.not_to raise_exception
    end

    it 'should fail if exception is received' do
      dummy_client = double(Aws::MQ::Client)
      mock_response = double(Object)
      allow(AwsHelper).to receive(:_amq_client).and_return(dummy_client)
      allow(AwsHelper).to receive(:sts_get_role_credentials)
      allow(dummy_client).to receive(:list_tags).and_return(mock_response)
      allow(mock_response).to receive(:tags).and_return(nil)
      allow(dummy_client).to receive(:create_tags).and_raise(RuntimeError)
      expect do
        AwsHelper.apply_amq_tags(
          resource_arn: 'test-arn',
          tags: {
            'QDAID' => 'C031'
          }
        )
      end.to raise_exception RuntimeError
    end
  end
end
