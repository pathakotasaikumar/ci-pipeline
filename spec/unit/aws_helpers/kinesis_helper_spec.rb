$LOAD_PATH.unshift("#{BASE_DIR}/lib/aws_helpers")
require 'kinesis_helper'

describe 'KinesisHelper' do
  context 'kinesis_set_retention_period_hours' do
    it 'successful execution - decrease retention period' do
      dummy_client = double(Aws::Kinesis::Client)
      allow(AwsHelper).to receive(:_kinesis_client).and_return(dummy_client)

      mock_response = double(Object)
      allow(dummy_client).to receive(:describe_stream).and_return(mock_response)

      mock_description = double(Object)
      allow(mock_response).to receive(:stream_description).and_return(mock_description)

      allow(mock_description).to receive(:retention_period_hours).and_return(72)
      allow(dummy_client).to receive(:decrease_stream_retention_period)
      expect {
        AwsHelper.kinesis_set_retention_period_hours(
          stream_name: 'dummy-stream',
          retention_period_hours: 24
        )
      }.not_to raise_exception
    end

    it 'successful execution - increase retention period' do
      dummy_client = double(Aws::Kinesis::Client)
      allow(AwsHelper).to receive(:_kinesis_client).and_return(dummy_client)

      mock_response = double(Object)
      allow(dummy_client).to receive(:describe_stream).and_return(mock_response)

      mock_description = double(Object)
      allow(mock_response).to receive(:stream_description).and_return(mock_description)

      allow(mock_description).to receive(:retention_period_hours).and_return(12)
      allow(dummy_client).to receive(:increase_stream_retention_period)
      expect {
        AwsHelper.kinesis_set_retention_period_hours(
          stream_name: 'dummy-stream',
          retention_period_hours: 24
        )
      }.not_to raise_exception
    end

    it 'successful execution - decrease retention period' do
      dummy_client = double(Aws::Kinesis::Client)
      allow(AwsHelper).to receive(:_kinesis_client).and_return(dummy_client)

      mock_response = double(Object)
      allow(dummy_client).to receive(:describe_stream).and_return(mock_response)

      mock_description = double(Object)
      allow(mock_response).to receive(:stream_description).and_return(mock_description)

      allow(mock_description).to receive(:retention_period_hours).and_return(24)
      expect(Log).to receive(:debug).with /Retention period for dummy-stream is left unchanged at 24/
      expect {
        AwsHelper.kinesis_set_retention_period_hours(
          stream_name: 'dummy-stream',
          retention_period_hours: 24
        )
      }.not_to raise_exception
    end
  end

  context '_kinesis_client' do
    it 'successful execution - initialize no provisioning or control credentials' do
      allow(Aws::Kinesis::Client).to receive(:new)
      allow(AwsHelper).to receive(:_provisioning_credentials)
      allow(AwsHelper).to receive(:_control_credentials)
      expect { AwsHelper._kinesis_client }.not_to raise_exception
    end

    it 'successful execution - initialize with provisioning credentials' do
      allow(Aws::Kinesis::Client).to receive(:new)
      mock_credentials = double(Object)
      allow(AwsHelper).to receive(:_provisioning_credentials).and_return(mock_credentials)
      allow(AwsHelper).to receive(:_control_credentials)
      expect { AwsHelper._kinesis_client }.not_to raise_exception
    end

    it 'successful execution - initialize with control credentials' do
      allow(Aws::Kinesis::Client).to receive(:new)
      mock_credentials = double(Object)
      allow(AwsHelper).to receive(:_provisioning_credentials)
      allow(AwsHelper).to receive(:_control_credentials).and_return(mock_credentials)
      expect { AwsHelper._kinesis_client }.not_to raise_exception
    end
  end
end
