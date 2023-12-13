$LOAD_PATH.unshift("#{BASE_DIR}/lib/aws_helpers")
require 'states_helper'

describe 'StatesHelper' do
  context 'states_client' do
    it 'initialize without error' do
      allow(Aws::States::Client).to receive(:new)
      allow(AwsHelper).to receive(:_provisioning_credentials)
      allow(AwsHelper).to receive(:_control_credentials)
      expect { AwsHelper._states_client }.not_to raise_exception
    end
  end

  context 'states_start_execution' do
    it 'successfully executes' do
      dummy_client = double(Aws::States::Client)
      dummy_execution_response = double(Object)
      allow(AwsHelper).to receive(:_states_client).and_return(dummy_client)
      allow(dummy_client).to receive(:start_execution).and_return(dummy_execution_response)
      allow(dummy_execution_response).to receive(:execution_arn).and_return('dummy-arn')
      expect(
        AwsHelper.states_start_execution(
          state_machine_arn: 'dummy-states-arn',
          input: '{"dummy":"input"}'
        )
      ).to eq('dummy-arn')
    end

    it 'fails to execute' do
      dummy_client = double(Aws::States::Client)
      allow(AwsHelper).to receive(:_states_client).and_return(dummy_client)
      allow(dummy_client).to receive(:start_execution).and_raise(StandardError)
      expect {
        AwsHelper.states_start_execution(
          state_machine_arn: 'dummy-states-arn',
          input: '{"dummy":"input"}'
        )
      }.to raise_exception /Unable to start execution for state machine/
    end

    it 'fails to execute with ArgumentError' do
      dummy_client = double(Aws::States::Client)
      allow(AwsHelper).to receive(:_states_client).and_return(dummy_client)
      expect { AwsHelper.states_start_execution }.to raise_exception ArgumentError
    end
  end

  context 'states_wait_until_complete' do
    it 'successfully executes' do
      dummy_client = double(Aws::States::Client)
      dummy_execution_response = double(Object)
      allow(AwsHelper).to receive(:_states_client).and_return(dummy_client)
      allow(dummy_client).to receive(:describe_execution).and_return(dummy_execution_response)
      allow(dummy_execution_response).to receive(:status).and_return('SUCCEEDED')
      allow(AwsHelper).to receive(:sleep)
      expect {
        AwsHelper.states_wait_until_complete(
          execution_arn: 'dummy-execution-arn'
        )
      }.not_to raise_exception
    end

    it 'fails with wrong status' do
      dummy_client = double(Aws::States::Client)
      dummy_execution_response = double(Object)
      allow(AwsHelper).to receive(:_states_client).and_return(dummy_client)
      allow(dummy_client).to receive(:describe_execution).and_return(dummy_execution_response)
      allow(dummy_execution_response).to receive(:status).and_return('FAILED')
      allow(AwsHelper).to receive(:sleep)
      expect {
        AwsHelper.states_wait_until_complete(
          execution_arn: 'dummy-execution-arn'
        )
      }.to raise_exception /has completed with status/
    end

    it 'fails with standard error' do
      dummy_client = double(Aws::States::Client)
      dummy_execution_response = double(Object)
      allow(AwsHelper).to receive(:_states_client).and_return(dummy_client)
      allow(dummy_client).to receive(:describe_execution).and_raise StandardError
      expect {
        AwsHelper.states_wait_until_complete(
          execution_arn: 'dummy-execution-arn'
        )
      }.to raise_exception StandardError
    end
  end

  context 'states_execution_result' do
    it 'successfully executes' do
      dummy_client = double(Aws::States::Client)
      dummy_execution_response = double(Object)
      allow(AwsHelper).to receive(:_states_client).and_return(dummy_client)
      allow(dummy_client).to receive(:describe_execution).and_return(dummy_execution_response)
      allow(dummy_execution_response).to receive(:output)
      expect {
        AwsHelper.states_execution_result('dummy-execution-arn')
      }.not_to raise_exception
    end

    it 'successfully executes' do
      dummy_client = double(Aws::States::Client)
      dummy_execution_response = double(Object)
      allow(AwsHelper).to receive(:_states_client).and_return(dummy_client)
      allow(dummy_client).to receive(:describe_execution).and_raise StandardError
      allow(dummy_execution_response).to receive(:output)
      expect { AwsHelper.states_execution_result('dummy-execution-arn') }.to raise_exception StandardError
    end
  end
end
