$LOAD_PATH.unshift("#{BASE_DIR}/lib/aws_helpers")
require 'kms_helper'

describe 'KMSHelper' do
  context '.kms_resolve_alias' do
    it 'throws expection if argument is not valid' do
      expect { AwsHelper.kms_resolve_alias(nil) }.to raise_error(ArgumentError)
      expect { AwsHelper.kms_resolve_alias() }.to raise_error(ArgumentError)
    end

    it 'returns kms_cmk_arn if kms_cmk_alias is valid' do
      mock_arn = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
      client = double(Aws::KMS::Client)
      describeKeyResponse = double(Aws::KMS::Types::DescribeKeyResponse)
      keyMetadata = double(Aws::KMS::Types::KeyMetadata, :arn => mock_arn)

      allow(AwsHelper).to receive(:_kms_client).and_return(client)
      allow(client).to receive(:describe_key) { :some_value }.and_return(describeKeyResponse)
      allow(describeKeyResponse).to receive(:key_metadata) {}.and_return(keyMetadata)

      expect(AwsHelper.kms_resolve_alias("test")).to eq mock_arn
    end

    it 'handles exceptions and cascades it to caller' do
      client = double(Aws::KMS::Client)
      allow(AwsHelper).to receive(:_kms_client).and_return(client)
      allow(client).to receive(:describe_key) { :some_value }.and_raise(Aws::KMS::Errors::NotFoundException.new("blah", "blah2"))
      expect(AwsHelper.kms_resolve_alias("test")).to eq nil
      allow(client).to receive(:describe_key) { :some_value }.and_raise(ArgumentError.new("blah"))
      expect { AwsHelper.kms_resolve_alias("test") }.to raise_error(ActionError)
    end
  end

  context '.kms_create_alias' do
    it 'throws expection if arguments are not valid' do
      # AwsHelper.kms_create_alias(kms_cmk_arn, kms_cmk_alias)
      expect { AwsHelper.kms_create_alias() }.to raise_error(ArgumentError)
    end

    it 'exits silently if kms_alias_key already exists' do
      allow(AwsHelper).to receive(:kms_resolve_alias).and_return('dummy-kms-arn')
      expect {
        AwsHelper.kms_create_alias(
          'dummy-kms-arn',
          'kms_cmk_alias'
        )
      }.not_to raise_error
    end

    it 'creates key if kms_alias_key is none' do
      client = double(Aws::KMS::Client)
      allow(AwsHelper).to receive(:kms_resolve_alias).and_return(nil)
      allow(AwsHelper).to receive(:_kms_client).and_return(client)
      allow(client).to receive(:create_alias) { :some_value }.and_return({})
      expect { AwsHelper.kms_create_alias('dummy-kms-arn', "kms_cmk_alias") }.not_to raise_error
    end

    it 'creates key if kms_alias_key is not matching' do
      client = double(Aws::KMS::Client)
      allow(AwsHelper).to receive(:kms_resolve_alias).and_return('dummy-non-matching-arn')
      allow(AwsHelper).to receive(:_kms_client).and_return(client)
      allow(client).to receive(:update_alias)
      expect { AwsHelper.kms_create_alias('dummy-kms-arn', 'kms_cmk_alias') }.not_to raise_error
    end

    it 'handles exceptions and cascades it to caller' do
      allow(AwsHelper).to receive(:kms_resolve_alias).and_raise(RuntimeError.new("blah"))
      expect { AwsHelper.kms_create_alias('dummy-kms-arn', "kms_cmk_alias") }.to raise_error(ActionError)
    end
  end

  context '.kms_encrypt_data' do
    it 'throws expection if arguments are not valid' do
      expect { AwsHelper.kms_encrypt_data() }.to raise_error(ArgumentError)
    end

    it 'encrypts data' do
      ciphertext_blob = "asdsd1239*^8asd!9"
      encryptResponse = double(Aws::KMS::Types::EncryptResponse, :ciphertext_blob => ciphertext_blob)

      client = double(Aws::KMS::Client)
      allow(AwsHelper).to receive(:_kms_client).and_return(client)
      allow(client).to receive(:encrypt) { :some_value }.and_return(encryptResponse)
      expect(AwsHelper.kms_encrypt_data("cmk", "blob")).to eq Base64.strict_encode64(ciphertext_blob)
    end
  end

  context '.kms_decrypt_data' do
    it 'throws expection if argument is not valid' do
      expect { AwsHelper.kms_decrypt_data() }.to raise_error(ArgumentError)
    end

    it 'decrypts data' do
      plaintext = "i am a plain text"
      client = double(Aws::KMS::Client)
      key_id = "1234abcd-12ab-34cd-56ef-1234567890ab"
      decryptResponse = double(Aws::KMS::Types::DecryptResponse, :plaintext => plaintext, :key_id => key_id)

      allow(AwsHelper).to receive(:_kms_client).and_return(client)
      allow(client).to receive(:decrypt) { :some_value }.and_return(decryptResponse)
      expect(AwsHelper.kms_decrypt_data("blob")).to eq plaintext
    end
  end

  context '.kms_generate_data_key_set' do
    it 'returns generateDataKeyResponse' do
      client = double(Aws::KMS::Client)
      generateDataKeyResponse = double(Aws::KMS::Types::GenerateDataKeyResponse,
                                       :ciphertext_blob => "asd",
                                       :plaintext => "pt",
                                       :key_id => "1234abcd-12ab-34cd-56ef-1234567890ab")

      allow(AwsHelper).to receive(:_kms_client).and_return(client)
      allow(client).to receive(:generate_data_key) { :some_value }.and_return(generateDataKeyResponse)

      expect { AwsHelper.kms_generate_data_key_set("cmk") }.not_to raise_error
    end
  end

  context '.kms_encrypt_data_local' do
    it 'encrypts data locally' do
      key_id = "1234abcd12ab34cd56ef1234567890ab"
      blob = "sample text"
      expect { AwsHelper.kms_encrypt_data_local(key_id, blob) }.not_to raise_error
    end
  end

  context '.kms_decrypt_data_local' do
    it 'decrypts data locally' do
      key = "1234abcd12ab34cd56ef1234567890ab"
      input = "sample text"
      blob, iv = AwsHelper.kms_encrypt_data_local(key, input)
      expect(AwsHelper.kms_decrypt_data_local(key, iv, blob)).to eq input
    end
  end

  context '_kms_client' do
    it 'successful execution - initialize no provisioning or control credentials' do
      allow(Aws::KMS::Client).to receive(:new)
      allow(AwsHelper).to receive(:_provisioning_credentials)
      allow(AwsHelper).to receive(:_control_credentials)
      expect { AwsHelper.send(:_kms_client) }.not_to raise_exception
    end

    it 'successful execution - initialize with provisioning credentials' do
      allow(Aws::KMS::Client).to receive(:new)
      mock_credentials = double(Object)
      allow(AwsHelper).to receive(:_provisioning_credentials).and_return(mock_credentials)
      allow(AwsHelper).to receive(:_control_credentials)
      expect { AwsHelper.send(:_kms_client) }.not_to raise_exception
    end

    it 'successful execution - initialize with control credentials' do
      allow(Aws::KMS::Client).to receive(:new)
      mock_credentials = double(Object)
      allow(AwsHelper).to receive(:_provisioning_credentials)
      allow(AwsHelper).to receive(:_control_credentials).and_return(mock_credentials)
      expect { AwsHelper.send(:_kms_client) }.not_to raise_exception
    end
  end
end
