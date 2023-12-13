$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}"))
require 'lib/consumables/pipeline_kms_key'
require 'lib/defaults'

RSpec.describe "PipelineKmsKey and AwsHelperClass" do
  before(:context) do
    cleanup_kms_stack
  end

  context 'PipelineKmsKey.deploy' do
    # Aws_Helper kms_create_alias, kms_resolve_alias are internally called by PipelineKmsKey.deploy
    it 'creates KMS Stack' do
      expect { PipelineKmsKey.deploy }.not_to raise_error
      expect(Context.kms.secrets_stack_id).to_not be_nil
      expect(Context.kms.secrets_key_arn).to_not be_nil
    end

    it 'does not create kms stack & alias if it already exists in stack' do
      Log.info "running deploy again"
      expect(Log).to receive(:info).with("Using existing KMS key")
      # resolved_alias = AwsHelper.kms_resolve_alias("alias/" + Defaults.sections[:plan_key].downcase)
      # expect(Log).to receive(:info).with("Not creating KMS key alias as it is already assoicated to '#{resolved_alias}'")
      PipelineKmsKey.deploy
    end
  end

  context 'AwsHelper.kms_encrypt_data' do
    it 'encrypts data into blob' do
      plain_text = "Lorem ipsum dolor sit amet, consectetur adipiscing elit."
      expect { AwsHelper.kms_encrypt_data(Context.kms.secrets_key_arn, plain_text) }.not_to raise_error
    end
  end

  context 'AwsHelper.kms_decrypt_data' do
    it 'decrypts data' do
      plain_text = "Lorem ipsum dolor sit amet, consectetur adipiscing elit."
      blob = AwsHelper.kms_encrypt_data(Context.kms.secrets_key_arn, plain_text)
      expect(AwsHelper.kms_decrypt_data(blob)).to eq plain_text
    end
  end

  context 'AwsHelper.kms_generate_data_key_set' do
    it 'returns generateDataKeyResponse' do
      data_key = nil
      expect {
        data_key = AwsHelper.kms_generate_data_key_set(Context.kms.secrets_key_arn)
      }.not_to raise_error

      Log.debug "Contents of AwsHelper.kms_generate_data_key_set(#{Context.kms.secrets_key_arn}) :\n #{data_key}"
    end
  end

  after(:all) do
    AwsHelper.cfn_delete_stack(Context.kms.secrets_stack_id)
  end
end
