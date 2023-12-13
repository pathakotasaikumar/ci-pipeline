$LOAD_PATH.unshift("#{BASE_DIR}/lib/aws_helpers")
require 'ecr_helper'

describe 'EcrHelper' do
  context '_ecr_client' do
    it 'successful execution - initialize no provisioning or control credentials' do
      allow(Aws::CloudFormation::Client).to receive(:new)
      allow(AwsHelper).to receive(:_provisioning_credentials)
      allow(AwsHelper).to receive(:_control_credentials)
      expect { AwsHelper._ecr_client }.not_to raise_exception
    end

    it 'successful execution - initialize with provisioning credentials' do
      allow(Aws::CloudFormation::Client).to receive(:new)
      mock_credentials = double(Object)
      allow(AwsHelper).to receive(:_provisioning_credentials).and_return(mock_credentials)
      allow(AwsHelper).to receive(:_control_credentials)
      expect { AwsHelper._ecr_client }.not_to raise_exception
    end

    it 'successful execution - initialize with control credentials' do
      allow(Aws::CloudFormation::Client).to receive(:new)
      mock_credentials = double(Object)
      allow(AwsHelper).to receive(:_provisioning_credentials)
      allow(AwsHelper).to receive(:_control_credentials).and_return(mock_credentials)
      expect { AwsHelper._ecr_client }.not_to raise_exception
    end
  end

  context 'ecr_get_authorisation_token' do
    it 'successful execution - ecr_get_authorisation_token' do
      dummy_client = double(Aws::ECR::Client)
      mock_response = double(Object) 

      allow(AwsHelper).to receive(:_ecr_client).and_return(dummy_client)
      allow(dummy_client).to receive(:get_authorization_token).and_return(mock_response)
      allow(mock_response).to receive_message_chain("authorization_data.first.authorization_token").and_return("AWS:123")
      
      expect {
        AwsHelper.ecr_get_authorisation_token()
      }.not_to raise_exception
    end    
  end

  context 'ecr_repository_exists' do
    it 'successful execution - ecr_repository_exists?' do
      dummy_client = double(Aws::ECR::Client)
      mock_response = double(Object) 

      allow(AwsHelper).to receive(:_ecr_client).and_return(dummy_client)
      allow(dummy_client).to receive(:describe_repositories).and_return("test")

      expect(Log).to receive(:info).with("ECR Repository test exists")
      expect {
        AwsHelper.ecr_repository_exists?("test")
      }.not_to raise_exception
    end
    
    it 'unsuccessful execution - ecr_repository_exists? exception happens' do
      dummy_client = double(Aws::ECR::Client)
      mock_response = double(Object) 
      allow(AwsHelper).to receive(:_ecr_client).and_return(dummy_client)
      allow(dummy_client).to receive(:describe_repositories).and_raise('Error - sorry')
      
      expect {
        AwsHelper.ecr_repository_exists?("test")
      }.to raise_error(/Error - sorry/)
    end
  end

  context 'ecr_set_repository_policy' do
    it 'successful execution - ecr_set_repository_policy' do
      dummy_client = double(Aws::ECR::Client)
      allow(AwsHelper).to receive(:_ecr_client).and_return(dummy_client)
      allow(dummy_client).to receive(:set_repository_policy)
      expect {
        AwsHelper.ecr_set_repository_policy(
          repository_name: "test",
          policy_text: "test"
        )
      }.not_to raise_exception
    end
  end

  context 'ecr_create_repository' do
    it 'successful execution - ecr_create_repository' do
      dummy_client = double(Aws::ECR::Client)
      allow(AwsHelper).to receive(:_ecr_client).and_return(dummy_client)
      allow(dummy_client).to receive(:create_repository)
      expect {
        AwsHelper.ecr_create_repository(
          repository_name: "test",
          image_tag_mutability: "MUTABLE",
          tags: {}
        )
      }.not_to raise_exception
    end
  end

  context 'ecr_put_image_scanning_configuration' do
    it 'successful execution - ecr_put_image_scanning_configuration' do
      dummy_client = double(Aws::ECR::Client)
      allow(AwsHelper).to receive(:_ecr_client).and_return(dummy_client)
      allow(dummy_client).to receive(:put_image_scanning_configuration)
      expect {
        AwsHelper.ecr_put_image_scanning_configuration(
          repository_name: "test",
          scan_on_push: true
        )
      }.not_to raise_exception
    end    
  end
end
