$LOAD_PATH.unshift("#{BASE_DIR}/lib/aws_helpers")
require 'cloudformation_helper'

describe 'CloudFormationHelper' do
  context '_cloudformation_client' do
    it 'successful execution - initialize no provisioning or control credentials' do
      allow(Aws::CloudFormation::Client).to receive(:new)
      allow(AwsHelper).to receive(:_provisioning_credentials)
      allow(AwsHelper).to receive(:_control_credentials)
      expect { AwsHelper._cloudformation_client }.not_to raise_exception
    end

    it 'successful execution - initialize with provisioning credentials' do
      allow(Aws::CloudFormation::Client).to receive(:new)
      mock_credentials = double(Object)
      allow(AwsHelper).to receive(:_provisioning_credentials).and_return(mock_credentials)
      allow(AwsHelper).to receive(:_control_credentials)
      expect { AwsHelper._cloudformation_client }.not_to raise_exception
    end

    it 'successful execution - initialize with control credentials' do
      allow(Aws::CloudFormation::Client).to receive(:new)
      mock_credentials = double(Object)
      allow(AwsHelper).to receive(:_provisioning_credentials)
      allow(AwsHelper).to receive(:_control_credentials).and_return(mock_credentials)
      expect { AwsHelper._cloudformation_client }.not_to raise_exception
    end
  end

  context '_cfn_get_and_log_stack_events' do
    it 'successful execution' do
      allow(AwsHelper).to receive(:_cfn_get_stack_events).and_return([])
      allow(AwsHelper).to receive(:_log_stack_events)
      mock_stack_event = double(Object)
      allow(mock_stack_event).to receive(:event_id)
      expect {
        AwsHelper._cfn_get_and_log_stack_events(
          'dummy-stack-id',
          [mock_stack_event]
        )
      }.not_to raise_exception
    end

    it 'fails with Log.warning' do
      allow(AwsHelper).to receive(:_cfn_get_stack_events)
      allow(AwsHelper).to receive(:_log_stack_events).and_raise(RuntimeError)
      expect {
        AwsHelper._cfn_get_and_log_stack_events(
          'dummy-stack-id',
          'dummy-stack-name'
        )
      }.not_to raise_exception
    end
  end

  context '_cfn_get_stack_status' do
    it 'successful execution' do
      cfn_mock_client = double(Object)
      cfn_mock_response = double(Object)
      cfn_mock_stack = double(Object)
      allow(AwsHelper).to receive(:_cloudformation_client).and_return(cfn_mock_client)
      allow(cfn_mock_client).to receive(:describe_stacks).and_return(cfn_mock_response)
      allow(cfn_mock_response).to receive(:stacks).and_return([cfn_mock_stack])
      allow(cfn_mock_stack).to receive(:stack_status)
      expect {
        AwsHelper._cfn_get_stack_status(
          stack_name: 'dummy-stack-name'
        )
      }.not_to raise_exception
    end

    it 'fails with Aws::CloudFormation::Errors::ValidationError' do
      cfn_mock_client = double(Object)
      allow(AwsHelper).to receive(:_cloudformation_client).and_return(cfn_mock_client)
      allow(cfn_mock_client).to receive(:describe_stacks).and_raise(
        Aws::CloudFormation::Errors::ValidationError.new(nil, "Stack does not exist")
      )
      expect {
        AwsHelper._cfn_get_stack_status(
          stack_name: 'dummy-stack-name'
        )
      }.not_to raise_exception
    end

    it 'fails with Failed to retrieve stack status for stack:' do
      cfn_mock_client = double(Object)
      allow(AwsHelper).to receive(:_cloudformation_client).and_return(cfn_mock_client)
      allow(cfn_mock_client).to receive(:describe_stacks).and_raise(RuntimeError)
      expect {
        AwsHelper._cfn_get_stack_status(
          stack_name: 'dummy-stack-name'
        )
      }.to raise_exception /Failed to retrieve stack status for stack/
    end
  end

  context '_cfn_get_stack_events' do
    it 'successful execution' do
      cfn_mock_client = double(Object)
      cfn_mock_response = double(Object)
      cfn_mock_event = double(Object)
      allow(AwsHelper).to receive(:_cloudformation_client).and_return(cfn_mock_client)
      allow(cfn_mock_client).to receive(:describe_stack_events).and_return(cfn_mock_response)
      allow(cfn_mock_response).to receive(:stack_events).and_return([cfn_mock_event])
      allow(cfn_mock_event).to receive(:event_id).and_return('dummy-event-id')
      expect {
        AwsHelper._cfn_get_stack_events(
          'dummy-stack-id'
        )
      }.not_to raise_exception
    end

    it 'fails with - Failed to retrieve stack events' do
      cfn_mock_client = double(Object)
      allow(AwsHelper).to receive(:_cloudformation_client).and_return(cfn_mock_client)
      allow(cfn_mock_client).to receive(:describe_stack_events).and_raise(RuntimeError)
      expect {
        AwsHelper._cfn_get_stack_events(
          'dummy-stack-id'
        )
      }.to raise_exception /Failed to retrieve stack events/
    end
  end

  context '_log_stack_events' do
    it 'successful execution' do
      cfn_mock_event = double(Object)
      allow(cfn_mock_event).to receive(:timestamp)
      allow(cfn_mock_event).to receive(:stack_name)
      allow(cfn_mock_event).to receive(:resource_type)
      allow(cfn_mock_event).to receive(:logical_resource_id)
      allow(cfn_mock_event).to receive(:resource_status)
      allow(cfn_mock_event).to receive(:resource_status_reason)
      expect {
        AwsHelper._log_stack_events(
          [cfn_mock_event]
        )
      }.not_to raise_exception
    end
  end

  context 'cfn_create_stack' do
    it 'successful execution' do
      cfn_mock_client = double(Object)
      cfn_mock_response = double(Object)
      cfn_mock_event = double(Object)
      allow(AwsHelper).to receive(:_cloudformation_client).and_return(cfn_mock_client)
      allow(cfn_mock_client).to receive(:create_stack).and_return(cfn_mock_response)
      allow(cfn_mock_response).to receive(:stack_id).and_return([cfn_mock_event])
      allow(cfn_mock_event).to receive(:event_id)
      ec2_mock_waiter = double(Object)
      allow(ec2_mock_waiter).to receive(:max_attempts=)
      allow(ec2_mock_waiter).to receive(:delay=)
      allow(cfn_mock_client).to receive(:wait_until) { |&block| block.call(ec2_mock_waiter) }
      ec2_mock_waiter2 = double(Object)
      allow(ec2_mock_waiter).to receive(:before_attempt) { |&block| block.call(ec2_mock_waiter2) }
      allow(AwsHelper).to receive(:_cfn_get_and_log_stack_events)
      allow(AwsHelper).to receive(:cfn_get_stack_outputs).and_return({})
      allow(AwsHelper).to receive(:sleep)
      expect {
        AwsHelper.cfn_create_stack(
          stack_name: 'dummy-stack',
          template: {},
          tags: []
        )
      }.not_to raise_exception
    end

    it 'successful execution with template_parameters' do
      cfn_mock_client = double(Object)
      cfn_mock_response = double(Object)
      cfn_mock_event = double(Object)
      allow(AwsHelper).to receive(:_cloudformation_client).and_return(cfn_mock_client)
      allow(cfn_mock_client).to receive(:create_stack).and_return(cfn_mock_response)
      allow(cfn_mock_response).to receive(:stack_id).and_return([cfn_mock_event])
      allow(cfn_mock_event).to receive(:event_id)
      ec2_mock_waiter = double(Object)
      allow(ec2_mock_waiter).to receive(:max_attempts=)
      allow(ec2_mock_waiter).to receive(:delay=)
      allow(cfn_mock_client).to receive(:wait_until) { |&block| block.call(ec2_mock_waiter) }
      ec2_mock_waiter2 = double(Object)
      allow(ec2_mock_waiter).to receive(:before_attempt) { |&block| block.call(ec2_mock_waiter2) }
      allow(AwsHelper).to receive(:_cfn_get_and_log_stack_events)
      allow(AwsHelper).to receive(:cfn_get_stack_outputs).and_return({})
      allow(AwsHelper).to receive(:cfn_parameter_list).and_return({})
      allow(AwsHelper).to receive(:sleep)
      expect {
        AwsHelper.cfn_create_stack(
          stack_name: 'dummy-stack',
          template: {},
          tags: [],
          template_parameters: { "key" => "value" }
        )
      }.not_to raise_exception
    end

    it 'fails with ArgumentError - stack_name' do
      expect {
        AwsHelper.cfn_create_stack(
          template: {},
          tags: []
        )
      }.to raise_exception(ArgumentError)
    end

    it 'fails with ArgumentError - template' do
      expect {
        AwsHelper.cfn_create_stack(
          stack_name: 'dummy-stack',
          tags: []
        )
      }.to raise_exception(ArgumentError)
    end

    it 'fails with ArgumentError - tags' do
      expect {
        AwsHelper.cfn_create_stack(
          stack_name: 'dummy-stack',
          template: {}
        )
      }.to raise_exception(ArgumentError)
    end

    it 'fails with - Creation of CloudFormation stack' do
      cfn_mock_client = double(Object)
      allow(AwsHelper).to receive(:_cloudformation_client).and_return(cfn_mock_client)
      allow(cfn_mock_client).to receive(:create_stack).and_raise(RuntimeError)
      expect {
        AwsHelper.cfn_create_stack(
          stack_name: 'dummy-stack',
          template: {},
          tags: []
        )
      }.to raise_exception /Creation of CloudFormation stack "dummy-stack" has failed/
    end

    it 'fails with - Aws::Waiters::Errors::TooManyAttemptsError ' do
      cfn_mock_client = double(Object)
      cfn_mock_response = double(Object)
      cfn_mock_event = double(Object)
      allow(AwsHelper).to receive(:_cloudformation_client).and_return(cfn_mock_client)
      allow(cfn_mock_client).to receive(:create_stack).and_return(cfn_mock_response)
      allow(cfn_mock_response).to receive(:stack_id).and_return([cfn_mock_event])
      allow(cfn_mock_event).to receive(:event_id)
      allow(cfn_mock_client).to receive(:wait_until).and_raise(Aws::Waiters::Errors::TooManyAttemptsError.new(1))
      allow(AwsHelper).to receive(:_cfn_get_and_log_stack_events)
      allow(AwsHelper).to receive(:sleep)
      expect {
        AwsHelper.cfn_create_stack(
          stack_name: 'dummy-stack',
          template: {},
          tags: []
        )
      }.to raise_exception(ActionError, /CloudFormation stack creation timed out/)
    end

    it 'fails with - Aws::Waiters::Errors::WaiterFailed ' do
      cfn_mock_client = double(Object)
      cfn_mock_response = double(Object)
      cfn_mock_event = double(Object)
      allow(AwsHelper).to receive(:_cloudformation_client).and_return(cfn_mock_client)
      allow(cfn_mock_client).to receive(:create_stack).and_return(cfn_mock_response)
      allow(cfn_mock_response).to receive(:stack_id).and_return([cfn_mock_event])
      allow(cfn_mock_event).to receive(:event_id)
      allow(cfn_mock_client).to receive(:wait_until).and_raise(Aws::Waiters::Errors::WaiterFailed)
      allow(AwsHelper).to receive(:_cfn_get_and_log_stack_events)
      allow(AwsHelper).to receive(:sleep)
      expect {
        AwsHelper.cfn_create_stack(
          stack_name: 'dummy-stack',
          template: {},
          tags: []
        )
      }.to raise_exception(ActionError, /CloudFormation stack creation failed/)
    end

    it 'fails with Failed to retrieve stack outputs after creation' do
      cfn_mock_client = double(Object)
      cfn_mock_response = double(Object)
      cfn_mock_event = double(Object)
      allow(AwsHelper).to receive(:_cloudformation_client).and_return(cfn_mock_client)
      allow(cfn_mock_client).to receive(:create_stack).and_return(cfn_mock_response)
      allow(cfn_mock_response).to receive(:stack_id).and_return([cfn_mock_event])
      allow(cfn_mock_event).to receive(:event_id)
      allow(cfn_mock_client).to receive(:wait_until)
      allow(AwsHelper).to receive(:_cfn_get_and_log_stack_events)
      allow(AwsHelper).to receive(:cfn_get_stack_outputs).and_raise(RuntimeError)
      allow(AwsHelper).to receive(:sleep)
      expect {
        AwsHelper.cfn_create_stack(
          stack_name: 'dummy-stack',
          template: {},
          tags: []
        )
      }.to raise_exception(ActionError, /Failed to retrieve stack outputs after creation/)
    end
  end

  context 'cfn_update_stack' do
    it 'successful execution' do
      cfn_mock_client = double(Object)
      cfn_mock_change_set = double(Object)
      cfn_mock_change_set_id = double(Object)
      cfn_mock_describe_response = double(Object)
      cfn_mock_change = double(Object)
      cfn_mock_resource_change = double(Object)
      allow(SecureRandom).to receive(:uuid)
      allow(AwsHelper).to receive(:_cloudformation_client).and_return(cfn_mock_client)
      allow(cfn_mock_client).to receive(:create_change_set).and_return(cfn_mock_change_set)
      allow(cfn_mock_change_set).to receive(:id).and_return(cfn_mock_change_set_id)
      allow(cfn_mock_client).to receive(:describe_change_set)
        .with(change_set_name: cfn_mock_change_set_id).and_return(cfn_mock_describe_response)
      allow(cfn_mock_describe_response).to receive(:status).and_return("CREATE_COMPLETE")
      allow(AwsHelper).to receive(:sleep)
      allow(cfn_mock_client).to receive(:changes).and_return([cfn_mock_change])
      allow(cfn_mock_describe_response).to receive(:changes).and_return([cfn_mock_change])
      allow(cfn_mock_change).to receive(:resource_change).and_return(cfn_mock_resource_change)
      allow(cfn_mock_describe_response).to receive(:stack_name).and_return('dummy-stack-name')
      allow(cfn_mock_resource_change).to receive(:action)
      allow(cfn_mock_resource_change).to receive(:resource_type)
      allow(cfn_mock_resource_change).to receive(:logical_resource_id)
      allow(cfn_mock_resource_change).to receive(:scope)
      allow(AwsHelper).to receive(:_cfn_get_stack_events)
      allow(cfn_mock_client).to receive(:execute_change_set)
      allow(AwsHelper).to receive(:sleep)
      ec2_mock_waiter = double(Object)
      allow(ec2_mock_waiter).to receive(:max_attempts=)
      allow(ec2_mock_waiter).to receive(:delay=)
      allow(cfn_mock_client).to receive(:wait_until) { |&block| block.call(ec2_mock_waiter) }
      ec2_mock_waiter2 = double(Object)
      allow(ec2_mock_waiter).to receive(:before_attempt) { |&block| block.call(ec2_mock_waiter2) }
      allow(AwsHelper).to receive(:_cfn_get_and_log_stack_events)
      allow(AwsHelper).to receive(:cfn_get_stack_outputs).and_return({})
      expect {
        AwsHelper.cfn_update_stack(
          stack_name: 'dummy-stack',
          template: {}
        )
      }.not_to raise_exception
    end

    it 'successful execution' do
      cfn_mock_client = double(Object)
      cfn_mock_change_set = double(Object)
      cfn_mock_change_set_id = double(Object)
      cfn_mock_describe_response = double(Object)
      allow(SecureRandom).to receive(:uuid)
      allow(AwsHelper).to receive(:_cloudformation_client).and_return(cfn_mock_client)
      allow(cfn_mock_client).to receive(:create_change_set).and_return(cfn_mock_change_set)
      allow(cfn_mock_change_set).to receive(:id).and_return(cfn_mock_change_set_id)
      allow(cfn_mock_client).to receive(:describe_change_set)
        .with(change_set_name: cfn_mock_change_set_id).and_return(cfn_mock_describe_response)
      allow(cfn_mock_describe_response).to receive(:status).and_return("CREATE_PENDING")
      allow(AwsHelper).to receive(:sleep)
      allow(cfn_mock_client).to receive(:delete_change_set)
      expect {
        AwsHelper.cfn_update_stack(
          stack_name: 'dummy-stack',
          template: {}
        )
      }.to raise_exception /Change set creation has timed out/
    end

    it 'successful execution - no changes' do
      cfn_mock_client = double(Object)
      cfn_mock_change_set = double(Object)
      cfn_mock_change_set_id = double(Object)
      cfn_mock_describe_response = double(Object)
      allow(SecureRandom).to receive(:uuid)
      allow(AwsHelper).to receive(:_cloudformation_client).and_return(cfn_mock_client)
      allow(cfn_mock_client).to receive(:create_change_set).and_return(cfn_mock_change_set)
      allow(cfn_mock_change_set).to receive(:id).and_return(cfn_mock_change_set_id)
      allow(cfn_mock_client).to receive(:describe_change_set)
        .with(change_set_name: cfn_mock_change_set_id).and_return(cfn_mock_describe_response)
      allow(cfn_mock_describe_response).to receive(:status).and_return("CREATE_COMPLETE")
      allow(cfn_mock_describe_response).to receive(:changes).and_return([])
      allow(cfn_mock_client).to receive(:delete_change_set)
      allow(AwsHelper).to receive(:cfn_get_stack_outputs).and_return({})
      expect {
        AwsHelper.cfn_update_stack(
          stack_name: 'dummy-stack',
          template: {}
        )
      }.not_to raise_exception
    end

    it 'fails with Aws::Waiters::Errors::TooManyAttemptsError' do
      cfn_mock_client = double(Object)
      cfn_mock_change_set = double(Object)
      cfn_mock_change_set_id = double(Object)
      cfn_mock_describe_response = double(Object)
      cfn_mock_change = double(Object)
      cfn_mock_resource_change = double(Object)
      allow(SecureRandom).to receive(:uuid)
      allow(AwsHelper).to receive(:_cloudformation_client).and_return(cfn_mock_client)
      allow(cfn_mock_client).to receive(:create_change_set).and_return(cfn_mock_change_set)
      allow(cfn_mock_change_set).to receive(:id).and_return(cfn_mock_change_set_id)
      allow(cfn_mock_client).to receive(:describe_change_set)
        .with(change_set_name: cfn_mock_change_set_id).and_return(cfn_mock_describe_response)
      allow(cfn_mock_describe_response).to receive(:status).and_return("CREATE_COMPLETE")
      allow(cfn_mock_client).to receive(:changes).and_return([cfn_mock_change])
      allow(cfn_mock_describe_response).to receive(:changes).and_return([cfn_mock_change])
      allow(cfn_mock_change).to receive(:resource_change).and_return(cfn_mock_resource_change)
      allow(cfn_mock_describe_response).to receive(:stack_name).and_return('dummy-stack-name')
      allow(cfn_mock_resource_change).to receive(:action)
      allow(cfn_mock_resource_change).to receive(:resource_type)
      allow(cfn_mock_resource_change).to receive(:logical_resource_id)
      allow(cfn_mock_resource_change).to receive(:scope)
      allow(AwsHelper).to receive(:_cfn_get_stack_events)
      allow(cfn_mock_client).to receive(:execute_change_set)
      allow(AwsHelper).to receive(:sleep)
      allow(cfn_mock_client).to receive(:wait_until).and_raise(Aws::Waiters::Errors::TooManyAttemptsError.new(1))
      expect {
        AwsHelper.cfn_update_stack(
          stack_name: 'dummy-stack',
          template: {}
        )
      }.to raise_exception ActionError, /CloudFormation stack update timed out/
    end

    it 'fails with Aws::Waiters::Errors::WaiterFailed ' do
      cfn_mock_client = double(Object)
      cfn_mock_change_set = double(Object)
      cfn_mock_change_set_id = double(Object)
      cfn_mock_describe_response = double(Object)
      cfn_mock_change = double(Object)
      cfn_mock_resource_change = double(Object)
      allow(SecureRandom).to receive(:uuid)
      allow(AwsHelper).to receive(:_cloudformation_client).and_return(cfn_mock_client)
      allow(cfn_mock_client).to receive(:create_change_set).and_return(cfn_mock_change_set)
      allow(cfn_mock_change_set).to receive(:id).and_return(cfn_mock_change_set_id)
      allow(cfn_mock_client).to receive(:describe_change_set)
        .with(change_set_name: cfn_mock_change_set_id).and_return(cfn_mock_describe_response)
      allow(cfn_mock_describe_response).to receive(:status).and_return("CREATE_COMPLETE")
      allow(cfn_mock_client).to receive(:changes).and_return([cfn_mock_change])
      allow(cfn_mock_describe_response).to receive(:changes).and_return([cfn_mock_change])
      allow(cfn_mock_change).to receive(:resource_change).and_return(cfn_mock_resource_change)
      allow(cfn_mock_describe_response).to receive(:stack_name).and_return('dummy-stack-name')
      allow(cfn_mock_resource_change).to receive(:action)
      allow(cfn_mock_resource_change).to receive(:resource_type)
      allow(cfn_mock_resource_change).to receive(:logical_resource_id)
      allow(cfn_mock_resource_change).to receive(:scope)
      allow(AwsHelper).to receive(:_cfn_get_stack_events)
      allow(cfn_mock_client).to receive(:execute_change_set)
      allow(AwsHelper).to receive(:sleep)
      allow(cfn_mock_client).to receive(:wait_until).and_raise(Aws::Waiters::Errors::WaiterFailed)
      expect {
        AwsHelper.cfn_update_stack(
          stack_name: 'dummy-stack',
          template: {}
        )
      }.to raise_exception ActionError, /CloudFormation stack update failed/
    end

    it 'fails with ArgumentError - stack_name' do
      expect {
        AwsHelper.cfn_create_stack(
          template: {}
        )
      }.to raise_exception(ArgumentError)
    end

    it 'fails with ArgumentError - template' do
      expect {
        AwsHelper.cfn_create_stack(
          stack_name: 'dummy-stack'
        )
      }.to raise_exception(ArgumentError)
    end
  end

  context 'cfn_stack_exists' do
    it 'successful execution' do
      cfn_mock_client = double(Object)
      cfn_mock_response = double(Object)
      cfn_mock_stack = double(Object)
      allow(AwsHelper).to receive(:_cloudformation_client).and_return(cfn_mock_client)
      allow(cfn_mock_client).to receive(:describe_stacks).and_return(cfn_mock_response)
      allow(cfn_mock_response).to receive(:stacks).and_return([cfn_mock_stack])
      allow(cfn_mock_stack).to receive(:stack_id)
      expect { AwsHelper.cfn_stack_exists('dummy-stack') }.not_to raise_exception
    end

    it 'successful execution' do
      cfn_mock_client = double(Object)
      cfn_mock_response = double(Object)
      cfn_mock_stack = double(Object)
      allow(AwsHelper).to receive(:_cloudformation_client).and_return(cfn_mock_client)
      allow(cfn_mock_client).to receive(:describe_stacks).and_return(cfn_mock_response)
      allow(cfn_mock_response).to receive(:stacks).and_return([cfn_mock_stack])
      allow(cfn_mock_stack).to receive(:stack_id)
      expect { AwsHelper.cfn_stack_exists('dummy-stack') }.not_to raise_exception
    end

    it 'fails with Aws::CloudFormation::Errors::ValidationError 1' do
      cfn_mock_client = double(Object)
      allow(AwsHelper).to receive(:_cloudformation_client).and_return(cfn_mock_client)
      allow(cfn_mock_client).to receive(:describe_stacks)
        .and_raise(Aws::CloudFormation::Errors::ValidationError.new(1, nil))
      expect { AwsHelper.cfn_stack_exists('dummy-stack') }.to raise_exception Aws::CloudFormation::Errors::ValidationError
    end

    it 'fails with Aws::CloudFormation::Errors::ValidationError 2' do
      cfn_mock_client = double(Object)
      allow(AwsHelper).to receive(:_cloudformation_client).and_return(cfn_mock_client)
      allow(cfn_mock_client).to receive(:describe_stacks)
        .and_raise(Aws::CloudFormation::Errors::ValidationError.new(1, 'stack does not exist'))
      expect { AwsHelper.cfn_stack_exists('dummy-stack') }.not_to raise_exception
    end

    it 'fails with An error occurred while checking if stack exists' do
      cfn_mock_client = double(Object)
      allow(AwsHelper).to receive(:_cloudformation_client).and_return(cfn_mock_client)
      allow(cfn_mock_client).to receive(:describe_stacks).and_raise(RuntimeError)
      expect { AwsHelper.cfn_stack_exists('dummy-stack') }
        .to raise_exception /An error occurred while checking if stack exists/
    end
  end

  context 'cfn_get_stack_outputs' do
    it 'successful execution' do
      cfn_mock_client = double(Object)
      cfn_mock_response = double(Object)
      cfn_mock_stack = double(Object)
      cfn_mock_stack_output = double(Object)
      allow(AwsHelper).to receive(:_cloudformation_client).and_return(cfn_mock_client)
      allow(cfn_mock_client).to receive(:describe_stacks).and_return(cfn_mock_response)
      allow(cfn_mock_response).to receive(:stacks).and_return([cfn_mock_stack])
      allow(cfn_mock_stack).to receive(:stack_id)
      allow(cfn_mock_stack).to receive(:stack_name)
      allow(cfn_mock_stack).to receive(:outputs).and_return([cfn_mock_stack_output])
      allow(cfn_mock_stack_output).to receive(:output_key).and_return('DummyOutputKey')
      allow(cfn_mock_stack_output).to receive(:output_value).and_return('DummyOutputValue')
      expect { AwsHelper.cfn_get_stack_outputs('dummy-stack') }.not_to raise_exception
    end

    it 'fails with - No stacks returned with name' do
      cfn_mock_client = double(Object)
      cfn_mock_response = double(Object)
      allow(AwsHelper).to receive(:_cloudformation_client).and_return(cfn_mock_client)
      allow(cfn_mock_client).to receive(:describe_stacks).and_return(cfn_mock_response)
      allow(cfn_mock_response).to receive(:stacks).and_return([])
      expect { AwsHelper.cfn_get_stack_outputs('dummy-stack') }
        .to raise_exception /No stacks returned with name dummy-stack/
    end

    it 'fails with - An error occurred while retrieving stack outputs' do
      cfn_mock_client = double(Object)
      cfn_mock_response = double(Object)
      allow(AwsHelper).to receive(:_cloudformation_client).and_return(cfn_mock_client)
      allow(cfn_mock_client).to receive(:describe_stacks).and_return(cfn_mock_response)
      allow(cfn_mock_response).to receive(:stacks).and_raise(RuntimeError)
      expect { AwsHelper.cfn_get_stack_outputs('dummy-stack') }
        .to raise_exception /An error occurred while retrieving stack outputs/
    end
  end

  context 'cfn_get_template' do
    it 'successful execution' do
      cfn_mock_client = double(Object)
      cfn_mock_response = double(Object)
      allow(AwsHelper).to receive(:_cloudformation_client).and_return(cfn_mock_client)
      allow(cfn_mock_client).to receive(:get_template).and_return(cfn_mock_response)
      allow(cfn_mock_response).to receive(:template_body)
      expect { AwsHelper.cfn_get_template('dummy-stack') }.not_to raise_exception
    end

    it 'fails with - An error occurred while retrieving the stack template' do
      cfn_mock_client = double(Object)
      cfn_mock_response = double(Object)
      allow(AwsHelper).to receive(:_cloudformation_client).and_return(cfn_mock_client)
      allow(cfn_mock_client).to receive(:get_template).and_raise(RuntimeError)
      allow(cfn_mock_response).to receive(:template_body)
      expect { AwsHelper.cfn_get_template('dummy-stack') }
        .to raise_exception /An error occurred while retrieving the stack template/
    end
  end

  context 'cfn_wait_until_stack_deletable' do
    it 'successful execution' do
      cfn_mock_client = double(Object)
      cfn_mock_response = double(Object)
      cfn_mock_stack = double(Object)
      allow(AwsHelper).to receive(:_cloudformation_client).and_return(cfn_mock_client)
      allow(cfn_mock_client).to receive(:describe_stacks).and_return(cfn_mock_response)
      allow(cfn_mock_response).to receive(:stacks).and_return([cfn_mock_stack])
      allow(cfn_mock_stack).to receive(:stack_status).and_return('ROLLBACK_COMPLETE')
      expect {
        AwsHelper.cfn_wait_until_stack_deletable(
          stack_name: 'dummy-stack'
        )
      }.not_to raise_exception
    end

    it 'fails with - Exceeded maximum number of attempts' do
      cfn_mock_client = double(Object)
      cfn_mock_response = double(Object)
      cfn_mock_stack = double(Object)
      allow(AwsHelper).to receive(:_cloudformation_client).and_return(cfn_mock_client)
      allow(cfn_mock_client).to receive(:describe_stacks).and_return(cfn_mock_response)
      allow(cfn_mock_response).to receive(:stacks).and_return([cfn_mock_stack])
      allow(cfn_mock_stack).to receive(:stack_status).and_return('ROLLBACK_IN_PROGRESS')
      allow(AwsHelper).to receive(:sleep)
      expect {
        AwsHelper.cfn_wait_until_stack_deletable(
          stack_name: 'dummy-stack',
          max_attempts: 5
        )
      }.to raise_exception /Exceeded maximum number of attempts/
    end

    it 'fails with - Expecting 1 matching stack, but found 2' do
      cfn_mock_client = double(Object)
      cfn_mock_response = double(Object)
      cfn_mock_stack = double(Object)
      allow(AwsHelper).to receive(:_cloudformation_client).and_return(cfn_mock_client)
      allow(cfn_mock_client).to receive(:describe_stacks).and_return(cfn_mock_response)
      allow(cfn_mock_response).to receive(:stacks).and_return([cfn_mock_stack, cfn_mock_stack])
      expect {
        AwsHelper.cfn_wait_until_stack_deletable(
          stack_name: 'dummy-stack'
        )
      }.to raise_exception /Expecting 1 matching stack, but found 2/
    end

    it 'fails with - Exceeded maximum number of attempts' do
      cfn_mock_client = double(Object)
      cfn_mock_response = double(Object)
      cfn_mock_stack = double(Object)
      allow(AwsHelper).to receive(:_cloudformation_client).and_return(cfn_mock_client)
      allow(cfn_mock_client).to receive(:describe_stacks).and_return(cfn_mock_response)
      allow(cfn_mock_response).to receive(:stacks).and_return([cfn_mock_stack])
      allow(cfn_mock_stack).to receive(:stack_status).and_return('ROLLBACK_IN_PROGRESS')
      expect {
        AwsHelper.cfn_wait_until_stack_deletable(
          stack_name: 'dummy-stack',
          max_attempts: 0
        )
      }.to raise_exception /Exceeded maximum number of attempts/
    end

    it 'pass with skip missing stack' do
      cfn_mock_client = double(Object)
      allow(AwsHelper).to receive(:_cloudformation_client).and_return(cfn_mock_client)
      allow(cfn_mock_client).to receive(:describe_stacks)
        .and_raise(Aws::CloudFormation::Errors::ValidationError.new(nil, "Stack does not exist"))
      allow(Context).to receive_message_chain("environment.variable").and_return(false)
      allow(Context).to receive_message_chain("environment.variable").with('cfn_skip_delete_on_missing', false).and_return(true)
      expect {
        AwsHelper.cfn_wait_until_stack_deletable(
          stack_name: 'dummy-stack',
        )
      }.not_to raise_exception
    end

    it 'fails with validation' do
      cfn_mock_client = double(Object)
      allow(AwsHelper).to receive(:_cloudformation_client).and_return(cfn_mock_client)
      allow(cfn_mock_client).to receive(:describe_stacks)
        .and_raise(Aws::CloudFormation::Errors::ValidationError.new(nil, "Stack does not exist"))
      allow(Context).to receive_message_chain("environment.variable").and_return(false)
      expect {
        AwsHelper.cfn_wait_until_stack_deletable(
          stack_name: 'dummy-stack',
        )
      }.to raise_exception /Failed cloudformation validation/
    end

    it 'fails with - Failed while waiting for stack to become deletable' do
      cfn_mock_client = double(Object)
      allow(AwsHelper).to receive(:_cloudformation_client).and_return(cfn_mock_client)
      allow(cfn_mock_client).to receive(:describe_stacks).and_raise(RuntimeError)
      expect {
        AwsHelper.cfn_wait_until_stack_deletable(
          stack_name: 'dummy-stack',
        )
      }.to raise_exception /Failed while waiting for stack to become deletable/
    end
  end

  context 'cfn_delete_stack' do
    it 'successful execution' do
      cfn_mock_client = double(Object)
      allow(AwsHelper).to receive(:cfn_wait_until_stack_deletable)
      allow(AwsHelper).to receive(:_cfn_get_stack_events)
      allow(AwsHelper).to receive(:_cloudformation_client).and_return(cfn_mock_client)
      allow(cfn_mock_client).to receive(:delete_stack)
      allow(AwsHelper).to receive(:sleep)
      ec2_mock_waiter = double(Object)
      allow(cfn_mock_client).to receive(:wait_until) { |&block| block.call(ec2_mock_waiter) }
      ec2_mock_waiter2 = double(Object)
      allow(ec2_mock_waiter).to receive(:before_attempt) { |&block| block.call(ec2_mock_waiter2) }
      expect { AwsHelper.cfn_delete_stack('dummy-stack') }.not_to raise_exception
    end

    it 'fails with ArgumentError' do
      expect { AwsHelper.cfn_delete_stack() }.to raise_exception(ArgumentError)
    end

    it 'fails with Failed to delete CloudFormation stack' do
      cfn_mock_client = double(Object)
      allow(AwsHelper).to receive(:cfn_wait_until_stack_deletable)
      allow(AwsHelper).to receive(:_cfn_get_stack_events)
      allow(AwsHelper).to receive(:_cloudformation_client).and_return(cfn_mock_client)
      allow(cfn_mock_client).to receive(:delete_stack).and_raise(RuntimeError)
      expect { AwsHelper.cfn_delete_stack('dummy-stack') }.to raise_exception /Failed to delete CloudFormation stack/
    end

    it 'passes deletion with skip missing' do
      cfn_mock_client = double(Object)
      allow(AwsHelper).to receive(:cfn_wait_until_stack_deletable)
      allow(AwsHelper).to receive(:_cfn_get_stack_events)
      allow(AwsHelper).to receive(:_cloudformation_client).and_return(cfn_mock_client)
      allow(cfn_mock_client).to receive(:delete_stack).and_raise("Stack does not exist")
      allow(Context).to receive_message_chain("environment.variable").and_return(false)
      allow(Context).to receive_message_chain("environment.variable").with('cfn_skip_delete_on_missing', false).and_return(true)
      expect { AwsHelper.cfn_delete_stack('dummy-stack') }.not_to raise_exception
    end

    it 'fails with Aws::Waiters::Errors::TooManyAttemptsError' do
      cfn_mock_client = double(Object)
      allow(AwsHelper).to receive(:cfn_wait_until_stack_deletable)
      allow(AwsHelper).to receive(:_cfn_get_stack_events)
      allow(AwsHelper).to receive(:_cloudformation_client).and_return(cfn_mock_client)
      allow(cfn_mock_client).to receive(:delete_stack)
      allow(AwsHelper).to receive(:sleep)
      allow(cfn_mock_client).to receive(:wait_until).and_raise(Aws::Waiters::Errors::TooManyAttemptsError.new(1))
      expect { AwsHelper.cfn_delete_stack('dummy-stack') }
        .to raise_exception(ActionError, /CloudFormation stack delete timed out/)
    end

    it 'fails with Aws::Waiters::Errors::WaiterFailed' do
      cfn_mock_client = double(Object)
      allow(AwsHelper).to receive(:cfn_wait_until_stack_deletable)
      allow(AwsHelper).to receive(:_cfn_get_stack_events)
      allow(AwsHelper).to receive(:_cloudformation_client).and_return(cfn_mock_client)
      allow(cfn_mock_client).to receive(:delete_stack)
      allow(AwsHelper).to receive(:sleep)
      allow(cfn_mock_client).to receive(:wait_until).and_raise(Aws::Waiters::Errors::WaiterFailed.new(1))
      expect { AwsHelper.cfn_delete_stack('dummy-stack') }
        .to raise_exception(ActionError, /CloudFormation stack delete failed/)
    end
  end

  context '._stack_event_error' do
    it 'detects error for CREATE_FAILED' do
      EventObject = Class.new do
        def initialize(resource_status)
          @resource_status = resource_status
        end

        def resource_status
          @resource_status
        end
      end

      ok1 = EventObject.new('CREATE_FAILED')
      ok2 = EventObject.new('CREATE_failed')

      expect(AwsHelper.__send__(:_stack_event_error?, nil)).to eq(false)
      expect(AwsHelper.__send__(:_stack_event_error?, 1)).to eq(false)

      expect(AwsHelper.__send__(:_stack_event_error?, ok1)).to eq(true)
      expect(AwsHelper.__send__(:_stack_event_error?, ok2)).to eq(true)
    end
  end
end
