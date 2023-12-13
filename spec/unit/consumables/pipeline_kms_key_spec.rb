$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib/consumables"))

require 'pipeline_kms_key'
require 'aws_helper_class'

RSpec.describe PipelineKmsKey do
  before(:context) do
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))
    @mock_arn = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"

    Context.kms.set_secrets_details(nil, nil)
  end

  context '._build_template' do
    it 'returns kms template' do
      sections = {
        ams: "ams99",
        qda: "c999",
        as: "99",
        env: "nonp",
      }
      allow(Defaults).to receive(:sections).and_return(sections)
      allow(Context).to receive_message_chain('environment.dr_account_id').and_return('123123123')
      allow(Context).to receive_message_chain('environment.nonp_account_id').and_return('123123124')
      expect(PipelineKmsKey._build_template).to eq @test_data["TestResult"]
    end
  end

  context '.deploy' do
    it 'deploys new KMS key' do
      allow(AwsHelper).to receive(:cfn_create_stack).and_return({ 'StackId' => 'stack-123', 'KeyArn' => 'my-arn' })
      allow(AwsHelper).to receive(:kms_create_alias).and_return(nil)
      allow(AwsHelper).to receive(:s3_put_object)
      allow(AwsHelper).to receive(:cfn_stack_exists).and_return(nil)
      allow(AwsHelper).to receive(:cfn_get_stack_outputs).and_return({ 'KeyArn' => nil })

      allow(Context).to receive_message_chain('environment.nonp_account_id').and_return('123123124')
      allow(Context).to receive_message_chain('environment.dr_account_id').and_return('123123123')
      allow(Context).to receive_message_chain('kms.set_secrets_details')
      allow(Context).to receive_message_chain('kms.secrets_key_arn').and_return(nil)

      expect { PipelineKmsKey.deploy }.not_to raise_error
    end

    it 'raises error on empty stack KMS key' do
      allow(AwsHelper).to receive(:cfn_create_stack).and_return({ 'StackId' => 'stack-123', 'KeyArn' => nil })
      allow(AwsHelper).to receive(:kms_create_alias).and_return(nil)
      allow(AwsHelper).to receive(:s3_put_object)
      allow(AwsHelper).to receive(:cfn_stack_exists).and_return(nil)
      allow(AwsHelper).to receive(:cfn_get_stack_outputs).and_return({ 'KeyArn' => nil })

      allow(Context).to receive_message_chain('environment.nonp_account_id').and_return('123123124')
      allow(Context).to receive_message_chain('environment.dr_account_id').and_return('123123123')
      allow(Context).to receive_message_chain('kms.set_secrets_details')
      allow(Context).to receive_message_chain('kms.secrets_key_arn').and_return(nil)

      expect { PipelineKmsKey.deploy }.to raise_error(/Stack did not output a KMS key ARN/)
    end

    it 'raises error on existing stack KMS key' do
      allow(AwsHelper).to receive(:cfn_create_stack).and_return({ 'StackId' => 'stack-123', 'KeyArn' => nil })
      allow(AwsHelper).to receive(:kms_create_alias).and_return(nil)
      allow(AwsHelper).to receive(:s3_put_object)
      allow(AwsHelper).to receive(:cfn_stack_exists).and_return(true)
      allow(AwsHelper).to receive(:cfn_get_stack_outputs).and_return({ 'KeyArn' => 'my-existing-key' })

      allow(Context).to receive_message_chain('environment.nonp_account_id').and_return('123123124')
      allow(Context).to receive_message_chain('environment.dr_account_id').and_return('123123123')
      allow(Context).to receive_message_chain('kms.set_secrets_details')
      allow(Context).to receive_message_chain('kms.secrets_key_arn').and_return(nil)

      allow(AwsHelper).to receive(:kms_create_alias).and_raise('Cannot create KMS key alias')

      expect { PipelineKmsKey.deploy }.to raise_error(/Cannot create KMS key alias/)
    end

    it 'deploys KMS resources as necessary & handles errors' do
      allow(AwsHelper).to receive(:cfn_create_stack).and_return({ 'StackId' => 'stack-123', 'KeyArn' => @mock_arn })
      allow(AwsHelper).to receive(:kms_create_alias).and_return(nil)
      allow(AwsHelper).to receive(:s3_put_object)
      allow(AwsHelper).to receive(:cfn_stack_exists).and_return(true)
      allow(AwsHelper).to receive(:cfn_get_stack_outputs).and_return({ 'KeyArn' => @mock_arn })

      allow(Context).to receive_message_chain('environment.dr_account_id').and_return('123123123')
      allow(Context).to receive_message_chain('environment.nonp_account_id').and_return('123123124')

      Context.kms.set_secrets_details(nil, nil)
      expect { PipelineKmsKey.deploy }.not_to raise_error

      expect(Context.kms.secrets_key_arn).to eq(@mock_arn)

      allow(AwsHelper).to receive(:cfn_stack_exists).and_return(nil)
      allow(AwsHelper).to receive(:cfn_create_stack).and_raise(ActionError.new({ 'StackId' => 'stack-456' }))

      Context.kms.set_secrets_details(nil, nil)

      expect { PipelineKmsKey.deploy }.to raise_error(/Failed to create KMS stack - ActionError/)
      expect(Context.kms.secrets_key_arn).to be_nil

      Context.kms.set_secrets_details(nil, nil)
    end
  end
end # RSpec.describe
