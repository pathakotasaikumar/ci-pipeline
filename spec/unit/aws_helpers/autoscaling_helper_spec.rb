$LOAD_PATH.unshift("#{BASE_DIR}/lib/aws_helpers")
require 'autoscaling_helper'

describe 'AutoscalingHelper' do
  context '_autoscaling_client' do
    it 'successful execution - initialize no provisioning or control credentials' do
      allow(Aws::CloudFormation::Client).to receive(:new)
      allow(AwsHelper).to receive(:_provisioning_credentials)
      allow(AwsHelper).to receive(:_control_credentials)
      expect { AwsHelper._autoscaling_client }.not_to raise_exception
    end

    it 'successful execution - initialize with provisioning credentials' do
      allow(Aws::CloudFormation::Client).to receive(:new)
      mock_credentials = double(Object)
      allow(AwsHelper).to receive(:_provisioning_credentials).and_return(mock_credentials)
      allow(AwsHelper).to receive(:_control_credentials)
      expect { AwsHelper._autoscaling_client }.not_to raise_exception
    end

    it 'successful execution - initialize with control credentials' do
      allow(Aws::CloudFormation::Client).to receive(:new)
      mock_credentials = double(Object)
      allow(AwsHelper).to receive(:_provisioning_credentials)
      allow(AwsHelper).to receive(:_control_credentials).and_return(mock_credentials)
      expect { AwsHelper._autoscaling_client }.not_to raise_exception
    end
  end

  context 'autoscaling_remove_instance_protection' do
    it 'successful execution' do
      dummy_client = double(Aws::AutoScaling::Client)
      mock_response = double(Object)
      mock_asg = double(Object)
      mock_instance = double(Object)
      allow(AwsHelper).to receive(:_autoscaling_client).and_return(dummy_client)
      allow(dummy_client).to receive(:describe_auto_scaling_groups).and_return(mock_response)
      allow(mock_response).to receive(:auto_scaling_groups).and_return([mock_asg])
      allow(mock_asg).to receive(:instances).and_return([mock_instance])
      allow(mock_instance).to receive(:protected_from_scale_in).and_return(true)
      allow(mock_instance).to receive(:instance_id).and_return('dummy-1234')
      allow(dummy_client).to receive(:set_instance_protection)
      expect {
        AwsHelper.autoscaling_remove_instance_protection(
          autoscaling_group_name: 'dummy-asg'
        )
      }.not_to raise_exception
    end
  end

  context 'clean_up_networkinterfaces' do
    it 'successful execution' do
      allow(Context).to receive_message_chain('component.variable').with('test', 'SecretManagementLambdaName', nil).and_return('ams01-c031-01-lambda-SecretManagementLambdaName')
      allow(Context).to receive_message_chain('component.variable').with('test', 'SecretManagementTerminationLambdaName', nil).and_return('ams01-c031-01-lambda-SecretManagementTerminationLambdaName')

      ec2_mock_interface = double(Object)
      ec2_mock_attachment = double(Object)
      allow(ec2_mock_interface).to receive(:attachment).and_return(ec2_mock_attachment)
      allow(ec2_mock_interface).to receive(:network_interface_id).and_return('eni-12345678')
      allow(ec2_mock_attachment).to receive(:attachment_id).and_return('dummy-attachment')

      allow(AwsHelper).to receive(:ec2_lambda_network_interfaces).and_return([ec2_mock_interface])
      allow(AwsHelper).to receive(:ec2_delete_network_interfaces)

      expect {
        AwsHelper.clean_up_networkinterfaces(
          component_name: 'test',
          autoscaling_group_name: 'dummy-asg'
        )
      }.not_to raise_exception
    end

    it 'failure execution' do
      allow(Context).to receive_message_chain('component.variable').with('test', 'SecretManagementLambdaName', nil).and_return('ams01-c031-01-lambda-SecretManagementLambdaName')
      allow(Context).to receive_message_chain('component.variable').with('test', 'SecretManagementTerminationLambdaName', nil).and_return('ams01-c031-01-lambda-SecretManagementTerminationLambdaName')

      ec2_mock_interface = double(Object)
      ec2_mock_attachment = double(Object)
      allow(ec2_mock_interface).to receive(:attachment).and_return(ec2_mock_attachment)
      allow(ec2_mock_interface).to receive(:network_interface_id).and_return('eni-12345678')
      allow(ec2_mock_attachment).to receive(:attachment_id).and_return('dummy-attachment')

      allow(AwsHelper).to receive(:ec2_lambda_network_interfaces).and_return([ec2_mock_interface])
      allow(AwsHelper).to receive(:ec2_delete_network_interfaces).and_raise(RuntimeError)
      expect(Log).to receive(:warn).with(/Failed to clean up network interfaces for "test" and autoscaling group name "dummy-asg" during teardown - RuntimeError/)
      expect {
        AwsHelper.clean_up_networkinterfaces(
          component_name: 'test',
          autoscaling_group_name: 'dummy-asg'
        )
      }.not_to raise_exception
    end

    it 'skip if no network interfaces found' do
      allow(Context).to receive_message_chain('component.variable').with('test', 'SecretManagementLambdaName', nil).and_return('ams01-c031-01-lambda-SecretManagementLambdaName')
      allow(Context).to receive_message_chain('component.variable').with('test', 'SecretManagementTerminationLambdaName', nil).and_return('ams01-c031-01-lambda-SecretManagementTerminationLambdaName')

      ec2_mock_interface = double(Object)
      ec2_mock_attachment = double(Object)
      allow(ec2_mock_interface).to receive(:attachment).and_return(ec2_mock_attachment)
      allow(ec2_mock_interface).to receive(:network_interface_id).and_return('eni-12345678')
      allow(ec2_mock_attachment).to receive(:attachment_id).and_return('dummy-attachment')

      allow(AwsHelper).to receive(:ec2_lambda_network_interfaces).and_return([])

      expect(Log).to receive(:debug).with(/Skipping cleanup - no network network interfaces found attached to "dummy-asg"/)

      expect {
        AwsHelper.clean_up_networkinterfaces(
          component_name: 'test',
          autoscaling_group_name: 'dummy-asg'
        )
      }.not_to raise_exception
    end

    it 'skip if lambda component name not found' do
      allow(Context).to receive_message_chain('component.variable').with('test', 'SecretManagementLambdaName', nil).and_return(nil)
      allow(Context).to receive_message_chain('component.variable').with('test', 'SecretManagementTerminationLambdaName', nil).and_return(nil)

      expect(Log).to receive(:debug).with(/Skipping cleanup - no network network interfaces found attached to autoscaling group \"dummy-asg\" lifecycle hook lambda./)

      expect {
        AwsHelper.clean_up_networkinterfaces(
          component_name: 'test',
          autoscaling_group_name: 'dummy-asg'
        )
      }.not_to raise_exception
    end
  end

  context 'autoscaling_set_capacity' do
    it 'successful execution' do
      dummy_client = double(Aws::AutoScaling::Client)
      allow(AwsHelper).to receive(:_autoscaling_client).and_return(dummy_client)
      allow(dummy_client).to receive(:update_auto_scaling_group)
      expect {
        AwsHelper.autoscaling_set_capacity(
          autoscaling_group_name: 'dummy-asg',
          min_size: 1
        )
      }.not_to raise_exception
    end

    it 'successful execution - skip no capacity params' do
      dummy_client = double(Aws::AutoScaling::Client)
      allow(AwsHelper).to receive(:_autoscaling_client).and_return(dummy_client)
      allow(dummy_client).to receive(:update_auto_scaling_group)
      expect {
        AwsHelper.autoscaling_set_capacity(
          autoscaling_group_name: 'dummy-asg'
        )
      }.not_to raise_exception
    end
  end

  context 'autoscaling_wait_for_capacity' do
    it 'successful execution - with Skipping wait for ASG to reach capacity - no min or max size was provided' do
      dummy_client = double(Aws::AutoScaling::Client)
      allow(AwsHelper).to receive(:_autoscaling_client).and_return(dummy_client)
      allow(dummy_client).to receive(:update_auto_scaling_group)
      expect(Log).to receive(:warn).with("Skipping wait for ASG to reach capacity - no min or max size was provided")
      expect {
        AwsHelper.autoscaling_wait_for_capacity(
          autoscaling_group_name: 'dummy-asg'
        )
      }.not_to raise_exception
    end

    it 'successful execution' do
      dummy_client = double(Aws::AutoScaling::Client)
      mock_response = double(Object)
      mock_asg = double(Object)
      mock_instance = double(Object)
      allow(AwsHelper).to receive(:_autoscaling_client).and_return(dummy_client)
      allow(dummy_client).to receive(:describe_auto_scaling_groups).and_return(mock_response)
      allow(mock_response).to receive(:auto_scaling_groups).and_return([mock_asg])
      allow(mock_asg).to receive(:instances).and_return([mock_instance])
      allow(mock_instance).to receive(:lifecycle_state).and_return('InService')
      allow(AwsHelper).to receive(:sleep)
      expect {
        AwsHelper.autoscaling_wait_for_capacity(
          autoscaling_group_name: 'dummy-asg',
          min_size: 1,
          max_size: 1,
          max_attempts: 1
        )
      }.not_to raise_exception
    end

    it 'fails with - ASG "dummy-asg" does not exist" ' do
      dummy_client = double(Aws::AutoScaling::Client)
      mock_response = double(Object)
      allow(AwsHelper).to receive(:_autoscaling_client).and_return(dummy_client)
      allow(dummy_client).to receive(:describe_auto_scaling_groups).and_return(mock_response)
      allow(mock_response).to receive(:auto_scaling_groups).and_return([])
      expect {
        AwsHelper.autoscaling_wait_for_capacity(
          autoscaling_group_name: 'dummy-asg',
          min_size: 1
        )
      }.to raise_exception /ASG "dummy-asg" does not exist/
    end

    it 'fails with - Timed out waiting for ASG to reach target capacity' do
      dummy_client = double(Aws::AutoScaling::Client)
      mock_response = double(Object)
      mock_asg = double(Object)
      mock_instance = double(Object)
      allow(AwsHelper).to receive(:_autoscaling_client).and_return(dummy_client)
      allow(dummy_client).to receive(:describe_auto_scaling_groups).and_return(mock_response)
      allow(mock_response).to receive(:auto_scaling_groups).and_return([mock_asg])
      allow(mock_asg).to receive(:instances).and_return([mock_instance])
      allow(mock_instance).to receive(:lifecycle_state).and_return('Pending')
      allow(AwsHelper).to receive(:sleep)
      expect {
        AwsHelper.autoscaling_wait_for_capacity(
          autoscaling_group_name: 'dummy-asg',
          min_size: 1,
          max_size: 1,
          max_attempts: 1
        )
      }.to raise_exception /Timed out waiting for ASG to reach target capacity/
    end
  end

  context '.describe_scaling_activities' do
    it 'executes' do
      data = {
        :test => "test_data"
      }

      dummy_client = double(Aws::AutoScaling::Client)
      allow(dummy_client).to receive(:describe_scaling_activities).and_return(data)
      allow(AwsHelper).to receive(:_autoscaling_client).and_return(dummy_client)

      res = AwsHelper.describe_scaling_activities(
        autoscaling_group_name: "test"
      )

      expect(res).to eq(data)
    end
  end
end
