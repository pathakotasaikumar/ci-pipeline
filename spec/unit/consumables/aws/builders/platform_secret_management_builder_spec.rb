require 'rspec'
$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws/builders")
require 'pipeline_autoscaling_action_builder'
require 'instance_builder'
require 'lambda_function_builder'
require 'platform_secret_management_builder'

RSpec.describe 'PlatformSecretManagementBuilder' do
  before(:context) do
    test_data_file = "#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"
    @test_data = YAML.load_file(
      test_data_file,
      permitted_classes: ['IamSecurityRule']
    )['UnitTest']
    @dummy_class = DummyClass.new
    @dummy_class.extend(PlatformSecretManagementBuilder)
  end

  context '_process_platform_secret_attachments' do
    it "retruns template for secret management attachment resources" do
      expected_output = @test_data['SecretManagementOutput']
      template = { "Resources" => {}, "Outputs" => {} }
      test_input = {
        template: template,
        autoscaling_group_name: "AutoscalingGroup",
        execution_role_arn: "arn:aws:iam:ap-southeast-2:111111111111:role/LambdaSecretManagementExecutionRole",
        notification_role_arn: "arn:aws:ap-southeast-2:111111111111:autoscaling:lifecyclehook",
        notification_attachments: [{ "ams" => "ams01", "qda" => "c031", "as" => "01", "ase" => "dev" }],
      }

      allow(Context).to receive_message_chain('environment.subnet_ids').and_return(['subnet-20008945', 'subnet-2123455'])
      allow(Context).to receive_message_chain('kms.secrets_key_arn')
        .and_return 'arn:aws:kms:ap-southeast-2:123456789012:key/12345678-1234-1234-1234-123456789012'

      allow(@dummy_class). to receive(:_prepare_and_upload_package_to_s3)
      @dummy_class._process_platform_secret_attachments(**test_input)

      expect(template).to eq expected_output
    end
  end

  context '_process_platform_secret_attachments_for_instance' do
    it "retruns template for secret management attachment resources" do
      expected_output = @test_data['SecretManagementInstanceOutput']
      template = { "Resources" => {}, "Outputs" => {} }
      environment_variable = {
        "KmsId" => "arn:aws:kms:ap-southeast-2:123456789012:key/12345678-1234-1234-1234-123456789012",
        "SecretsStorageBucket" => "qcp-secret",
        "SecretsStorageFileLocation" => "qcp-secret-location"
      }
      test_input = {
        template: template,
        execution_role_arn: "arn:aws:iam:ap-southeast-2:111111111111:role/LambdaSecretManagementExecutionRole",
        resource_name: "SecretManagementLambda",
        environment_variables: environment_variable,
      }

      allow(Context).to receive_message_chain('environment.subnet_ids').and_return(['subnet-20008945', 'subnet-2123455'])
      allow(Context).to receive_message_chain('kms.secrets_key_arn')
        .and_return 'arn:aws:kms:ap-southeast-2:123456789012:key/12345678-1234-1234-1234-123456789012'
      allow(Context).to receive_message_chain('asir.destination_sg_id').and_return('sg-123456')
      allow(@dummy_class). to receive(:_prepare_and_upload_package_to_s3)
      @dummy_class._process_platform_secret_attachments_for_instance(**test_input)

      expect(template).to eq expected_output
    end
  end

  context '_platform_secret_attachment_security_rules' do
    it 'return _platform_secret_attachment_security_rules ' do
      expected_output = @test_data['SecurityRules']
      allow(Context).to receive_message_chain('kms.secrets_key_arn').and_return('arn:/secrets_key_arn')
      actual_output = @dummy_class._platform_secret_attachment_security_rules(component_name: "TestComponent", execution_role_name: "LambdaSecretManagementExecutionRole")
      expect(actual_output).to eq(expected_output)
    end
  end

  context '_platform_secrets_metadata' do
    it 'return _platform_secrets_metadata ' do
      expected_output = @test_data['Platform_secrets_metadata']
      allow(Context).to receive_message_chain('kms.secrets_key_arn').and_return('arn:/secrets_key_arn')
      actual_output = @dummy_class._platform_secrets_metadata
      expect(actual_output).to eq(expected_output)
    end
  end

  context '._upload_package_artefact' do
    it 'fails to locate artefact' do
      allow(Context).to receive_message_chain('s3.lambda_artefact_bucket_name').and_return('arn:aws:s3:::qf-ams01-c031-n-01')
      allow(Defaults).to receive(:cd_artefact_path).and_return('cd/ams01/c031/01/dev/master/1')
      allow(File).to receive(:exist?).and_return(false)
      expect { @dummy_class.send(:_upload_package_artefact, 'platform.zip', 'test') }.to raise_error(/Unable to locate platform.zip/)
    end

    it 'fails to upload the artefact' do
      allow(Context).to receive_message_chain('s3.lambda_artefact_bucket_name').and_return('arn:aws:s3:::qf-ams01-c031-n-01')
      allow(Defaults).to receive(:cd_artefact_path).and_return('cd/ams01/c031/01/dev/master/1')
      allow(File).to receive(:exist?).and_return(true)
      allow(File).to receive(:basename).and_return('platform.zip')
      allow(AwsHelper).to receive(:s3_upload_file).and_raise(/Failed to upload/)
      expect { @dummy_class.send(:_upload_package_artefact, 'platform.zip', 'test') }.to raise_error(/Unable to upload/)
    end

    it 'successfully upload lambda package artefact' do
      allow(Context).to receive_message_chain('s3.lambda_artefact_bucket_name').and_return('arn:aws:s3:::qf-ams01-c031-n-01')
      allow(Defaults).to receive(:cd_artefact_path).and_return('cd/ams01/c031/01/dev/master/1')
      allow(AwsHelper).to receive(:s3_download_object)
      allow(File).to receive(:exist?).and_return(true)
      allow(File).to receive(:basename).and_return('platform.zip')
      allow(AwsHelper).to receive(:s3_upload_file)
      expect { @dummy_class.send(:_upload_package_artefact, 'platform.zip', 'test') }.not_to raise_error
    end
  end

  context '._prepare_and_upload_package_to_s3' do
    it 'successfully create zip file' do
      allow(@dummy_class).to receive(:_upload_package_artefact)
      expect { @dummy_class.send(:_prepare_and_upload_package_to_s3, component_name: 'test') }.not_to raise_error
    end
  end
end
