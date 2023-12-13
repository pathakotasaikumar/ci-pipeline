$LOAD_PATH.unshift("#{BASE_DIR}/lib/aws_helpers")
require 'application_autoscaling_helper'

describe 'ApplicationAutoscalingHelper' do
  context '_application_autoscaling_client' do
    it 'successful execution - initialize no provisioning or control credentials' do
      allow(Aws::CloudFormation::Client).to receive(:new)
      allow(AwsHelper).to receive(:_provisioning_credentials)
      allow(AwsHelper).to receive(:_control_credentials)
      expect { AwsHelper._application_autoscaling_client }.not_to raise_exception
    end

    it 'successful execution - initialize with provisioning credentials' do
      allow(Aws::CloudFormation::Client).to receive(:new)
      mock_credentials = double(Object)
      allow(AwsHelper).to receive(:_provisioning_credentials).and_return(mock_credentials)
      allow(AwsHelper).to receive(:_control_credentials)
      expect { AwsHelper._application_autoscaling_client }.not_to raise_exception
    end

    it 'successful execution - initialize with control credentials' do
      allow(Aws::CloudFormation::Client).to receive(:new)
      mock_credentials = double(Object)
      allow(AwsHelper).to receive(:_provisioning_credentials)
      allow(AwsHelper).to receive(:_control_credentials).and_return(mock_credentials)
      expect { AwsHelper._application_autoscaling_client }.not_to raise_exception
    end
  end

  context 'scalable_target_wait_for_capacity' do
    it 'successful execution - with Skipping wait for scalable target to reach capacity - no scalable_target_id was provided' do
      dummy_client = double(Aws::ApplicationAutoScaling::Client)
      allow(AwsHelper).to receive(:_application_autoscaling_client).and_return(dummy_client)
      expect(Log).to receive(:warn).with("Skipping wait for scalable target to reach capacity - no scalable_target_id was provided")
      expect {
        AwsHelper.scalable_target_wait_for_capacity()
      }.not_to raise_exception
    end

    it 'successful execution - with Skipping wait for scalable target to reach capacity - no service_namespace was provided' do
      dummy_client = double(Aws::ApplicationAutoScaling::Client)
      allow(AwsHelper).to receive(:_application_autoscaling_client).and_return(dummy_client)
      expect(Log).to receive(:warn).with("Skipping wait for scalable target to reach capacity - no service_namespace was provided")
      expect {
        AwsHelper.scalable_target_wait_for_capacity(
          scalable_target_id: 'test'
        )
      }.not_to raise_exception
    end

    it 'successful execution - with Skipping wait for scalable target to reach capacity - no min or max size was provided' do
      dummy_client = double(Aws::ApplicationAutoScaling::Client)
      allow(AwsHelper).to receive(:_application_autoscaling_client).and_return(dummy_client)
      expect(Log).to receive(:warn).with("Skipping wait for scalable target to reach capacity - no min or max size was provided")
      expect {
        AwsHelper.scalable_target_wait_for_capacity(
          service_namespace: 'test',  
          scalable_target_id: 'test'
        )
      }.not_to raise_exception
    end

    it 'fails with - scalable target "dummy_scalable_target_id" does not exist" ' do
      dummy_client = double(Aws::ApplicationAutoScaling::Client)
      mock_response = double(Object)      
      mock_scalable_targets_response = double(Object)
      allow(AwsHelper).to receive(:_application_autoscaling_client).and_return(dummy_client)
      allow(dummy_client).to receive(:describe_scalable_targets).and_return(mock_scalable_targets_response)
      allow(mock_scalable_targets_response).to receive(:scalable_targets).and_return(nil)
      
      # allow(mock_response).to receive(:scaling_activities).and_return([])
      expect {
        AwsHelper.scalable_target_wait_for_capacity(          
          service_namespace: "dummy_service_namespace",  
          scalable_target_id: "dummy_scalable_target_id",
          min_capacity: 1
        )
      }.to raise_exception "scalable target dummy_scalable_target_id does not exist"
    end

    it 'successful execution' do
      dummy_client = double(Aws::ApplicationAutoScaling::Client)
      mock_response = double(Object)      
      mock_scalable_targets_response = double(Object)
      mock_scaling_activities_response = double(Object)
      mock_scaling_activities = double(Object)
      allow(AwsHelper).to receive(:_application_autoscaling_client).and_return(dummy_client)
      allow(dummy_client).to receive(:describe_scalable_targets).and_return(mock_scalable_targets_response)
      allow(mock_scalable_targets_response).to receive(:scalable_targets).and_return('dummy_scalable_targets')
      allow(dummy_client).to receive(:describe_scaling_activities).and_return(mock_scaling_activities_response)
      allow(mock_scaling_activities_response).to receive(:scaling_activities).and_return([mock_scaling_activities])
      allow(mock_scaling_activities).to receive(:status_code).and_return('Successful')
      allow(AwsHelper).to receive(:sleep)
      expect {
        AwsHelper.scalable_target_wait_for_capacity(
          service_namespace: "dummy_service_namespace",  
          scalable_target_id: "dummy_scalable_target_id",       
          min_capacity: 1,
          max_capacity: 1,
          max_attempts: 1    
        )
      }.not_to raise_exception
    end

    it 'fails with - Timed out waiting to reach target capacity' do
      dummy_client = double(Aws::ApplicationAutoScaling::Client)
      mock_response = double(Object)      
      mock_scalable_targets_response = double(Object)
      mock_scaling_activities_response = double(Object)
      mock_scaling_activities = double(Object)
      allow(AwsHelper).to receive(:_application_autoscaling_client).and_return(dummy_client)
      allow(dummy_client).to receive(:describe_scalable_targets).and_return(mock_scalable_targets_response)
      allow(mock_scalable_targets_response).to receive(:scalable_targets).and_return('dummy_scalable_targets')
      allow(dummy_client).to receive(:describe_scaling_activities).and_return(mock_scaling_activities_response)
      allow(mock_scaling_activities_response).to receive(:scaling_activities).and_return([mock_scaling_activities])
      allow(mock_scaling_activities).to receive(:status_code).and_return('Pending')
      allow(AwsHelper).to receive(:sleep)
      expect {
        AwsHelper.scalable_target_wait_for_capacity(
          service_namespace: "dummy_service_namespace",  
          scalable_target_id: "dummy_scalable_target_id",       
          min_capacity: 1,
          max_capacity: 1,
          max_attempts: 1
        )
      }.to raise_exception "Timed out waiting to reach target capacity"
    end
  end
end
