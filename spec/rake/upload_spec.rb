$LOAD_PATH.unshift("#{BASE_DIR}/lib")
require "rake"

RSpec.describe 'rake' do
  # getting shared context for the tests
  require_relative 'shared_context.rb'

  describe 'upload:all' do
    let(:task_paths) { ['upload'] }
    let(:task_name) { 'upload:all' }
    include_context 'rake'

    it 'failed [enforce] validation fails' do
      # [enforce] + exception fails :all task
      expected_error = /Component validation has encountered an error, failing build/

      allow(Context).to receive_message_chain('environment.variables')
        .and_return({})

      # this one is called within validation task
      # returning 'enforce' mode
      allow(Context).to receive_message_chain('environment.variable')
        .with('validation_mode', 'report')
        .and_return('enforce')

      # emulating exception within validation task
      allow(ComponentValidator).to receive(:new) .and_raise('failing ComponentValidator')

      allow(AwsHelper).to receive(:s3_delete_objects)
      allow(AwsHelper).to receive(:s3_upload_file)

      # component validation error should be raised and fail :all task
      expect { subject.invoke }.to raise_error(expected_error)
    end

    it 'passed [enforce] validation passes' do
      # [enforce] + no exception passes :all task
      allow(Context).to receive_message_chain('environment.variables')
        .and_return({})

      # this one is called within validation task
      # returning 'enforce' mode
      allow(Context).to receive_message_chain('environment.variable')
        .with('validation_mode', 'report')
        .and_return('enforce')

      allow(AwsHelper).to receive(:s3_delete_objects)
      allow(AwsHelper).to receive(:s3_upload_file)

      # component validation error should be raised and fail :all task
      expect { subject.invoke }.to_not raise_error
    end

    it 'failed [report] validation passes' do
      # [report] + exception passes :all task
      allow(Context).to receive_message_chain('environment.variables')
        .and_return({})

      # this one is called within validation task
      # returning 'enforce' mode
      allow(Context).to receive_message_chain('environment.variable')
        .with('validation_mode', 'report')
        .and_return('report')

      # emulating exception within validation task
      allow(ComponentValidator).to receive(:new) .and_raise('failing ComponentValidator')

      allow(AwsHelper).to receive(:s3_delete_objects)
      allow(AwsHelper).to receive(:s3_upload_file)

      # component validation error should be raised and fail :all task
      expect { subject.invoke }.to_not raise_error
    end

    it 'passed [report] validation passes' do
      # [report] + exception passes :all task
      allow(Context).to receive_message_chain('environment.variables')
        .and_return({})

      # this one is called within validation task
      # returning 'enforce' mode
      allow(Context).to receive_message_chain('environment.variable')
        .with('validation_mode', 'report')
        .and_return('report')

      allow(AwsHelper).to receive(:s3_delete_objects)
      allow(AwsHelper).to receive(:s3_upload_file)

      # component validation error should be raised and fail :all task
      expect { subject.invoke }.to_not raise_error
    end
  end
end # RSpec.describe
