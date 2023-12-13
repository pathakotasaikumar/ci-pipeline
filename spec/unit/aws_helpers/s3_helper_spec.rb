$LOAD_PATH.unshift("#{BASE_DIR}/lib/aws_helpers")
require 's3_helper'
require 'aws-sdk'

RSpec.describe 'S3Helper' do
  before(:context) do
    @mock_data = [*1..1337].map { |e| { key: "file#{e}" } }
  end

  context '_s3_helper_init' do
    it 'successful execution' do
      expect { AwsHelper._s3_helper_init('dummy-role') }.not_to raise_exception
    end
  end

  context 's3_put_object' do
    it 'successful execution' do
      allow(Digest::SHA256).to receive(:base64digest)
      allow(Digest::MD5).to receive(:base64digest)
      allow(AwsHelper).to receive(:_s3_upload)
      expect {
        AwsHelper.s3_put_object(
          'dummy_bucket',
          'dummy-key',
          'dummy-data'
        )
      }.not_to raise_exception
    end

    it 'fails with argument error - bucket non string' do
      allow(Digest::SHA256).to receive(:base64digest)
      allow(Digest::MD5).to receive(:base64digest)
      allow(AwsHelper).to receive(:_s3_upload)
      expect {
        AwsHelper.s3_put_object(
          1,
          'dummy-key',
          'dummy-data'
        )
      }.to raise_exception ArgumentError
    end

    it 'fails with argument error - bucket empty' do
      allow(Digest::SHA256).to receive(:base64digest)
      allow(Digest::MD5).to receive(:base64digest)
      allow(AwsHelper).to receive(:_s3_upload)
      expect {
        AwsHelper.s3_put_object(
          '',
          'dummy-key',
          'dummy-data'
        )
      }.to raise_exception ArgumentError
    end

    it 'fails with argument error - key non string' do
      allow(Digest::SHA256).to receive(:base64digest)
      allow(Digest::MD5).to receive(:base64digest)
      allow(AwsHelper).to receive(:_s3_upload)
      expect {
        AwsHelper.s3_put_object(
          'dummy_bucket',
          1,
          'dummy-data'
        )
      }.to raise_exception ArgumentError
    end

    it 'fails with argument error - key empty' do
      allow(Digest::SHA256).to receive(:base64digest)
      allow(Digest::MD5).to receive(:base64digest)
      allow(AwsHelper).to receive(:_s3_upload)
      expect {
        AwsHelper.s3_put_object(
          'dummy_bucket',
          '',
          'dummy-data'
        )
      }.to raise_exception ArgumentError
    end
  end

  context 's3_upload_file' do
    it 'successful execution' do
      allow(Digest::SHA256).to receive_message_chain('file.base64digest')
      allow(Digest::MD5).to receive_message_chain('file.base64digest')
      allow(AwsHelper).to receive(:_s3_upload)
      allow(File).to receive(:file?).and_return(true)
      allow(File).to receive(:open)
      expect {
        AwsHelper.s3_upload_file(
          'dummy_bucket',
          'dummy-key',
          'dummy-data'
        )
      }.not_to raise_exception
    end

    it 'fails with argument error - invalid file path' do
      allow(Digest::SHA256).to receive_message_chain('file.base64digest')
      allow(Digest::MD5).to receive_message_chain('file.base64digest')
      allow(AwsHelper).to receive(:_s3_upload)
      allow(File).to receive(:file?).and_return false
      expect {
        AwsHelper.s3_upload_file(
          'dummy_bucket',
          'dummy-key',
          'dummy-data'
        )
      }.to raise_exception ArgumentError
    end

    it 'fails with argument error - bucket non string' do
      allow(Digest::SHA256).to receive(:base64digest)
      allow(Digest::MD5).to receive(:base64digest)
      allow(AwsHelper).to receive(:_s3_upload)
      expect {
        AwsHelper.s3_upload_file(
          1,
          'dummy-key',
          'dummy-data'
        )
      }.to raise_exception ArgumentError
    end

    it 'fails with argument error - bucket empty' do
      allow(Digest::SHA256).to receive(:base64digest)
      allow(Digest::MD5).to receive(:base64digest)
      allow(AwsHelper).to receive(:_s3_upload)
      expect {
        AwsHelper.s3_upload_file(
          '',
          'dummy-key',
          'dummy-data'
        )
      }.to raise_exception ArgumentError
    end

    it 'fails with argument error - key non string' do
      allow(Digest::SHA256).to receive(:base64digest)
      allow(Digest::MD5).to receive(:base64digest)
      allow(AwsHelper).to receive(:_s3_upload)
      expect {
        AwsHelper.s3_upload_file(
          'dummy_bucket',
          1,
          'dummy-data'
        )
      }.to raise_exception ArgumentError
    end

    it 'fails with argument error - key empty' do
      allow(Digest::SHA256).to receive(:base64digest)
      allow(Digest::MD5).to receive(:base64digest)
      allow(AwsHelper).to receive(:_s3_upload)
      expect {
        AwsHelper.s3_upload_file(
          'dummy_bucket',
          '',
          'dummy-data'
        )
      }.to raise_exception ArgumentError
    end
  end

  context 's3_get_object' do
    it 'successful execution' do
      mock_client = double(Object)
      allow(AwsHelper).to receive(:_s3_client).and_return(mock_client)
      mock_response = double(Object)
      allow(mock_client).to receive(:get_object).and_return(mock_response)
      allow(mock_response).to receive_message_chain('body.read')
      allow(Digest::SHA256).to receive(:base64digest).and_return('dummy-check-sum')
      allow(mock_response).to receive(:metadata).and_return({ 'checksum' => 'dummy-check-sum' })
      allow(mock_response).to receive(:version_id)
      expect {
        AwsHelper.s3_get_object(
          'dummy_bucket',
          'dummy-key',
          'dummy-version'
        )
      }.not_to raise_exception
    end

    it 'fails with argument error' do
      mock_client = double(Object)
      allow(AwsHelper).to receive(:_s3_client).and_return(mock_client)
      mock_response = double(Object)
      allow(mock_client).to receive(:get_object).and_return(mock_response)
      allow(mock_response).to receive_message_chain('body.read').and_raise(StandardError)
      expect {
        AwsHelper.s3_get_object(
          'dummy_bucket',
          'dummy-key',
          'dummy-version'
        )
      }.to raise_exception /Failed to download object/
    end
  end

  context 's3_download_object' do
    it 'successful execution' do
      allow(FileUtils).to receive(:mkdir_p)
      allow(File).to receive(:dirname)

      mock_client = double(Object)
      allow(AwsHelper).to receive(:_s3_client).and_return(mock_client)
      mock_response = double(Object)
      allow(mock_client).to receive(:get_object).and_return(mock_response)

      allow(Digest::SHA256).to receive_message_chain('file.base64digest').and_return('dummy-checksum')
      allow(mock_response).to receive(:metadata).and_return({ 'checksum' => 'dummy-checksum' })

      expect {
        AwsHelper.s3_download_object(
          bucket: 'dummy_bucket',
          key: 'dummy-key'
        )
      }      .not_to raise_exception
    end

    it 'successful execution - different checksum' do
      allow(FileUtils).to receive(:mkdir_p)
      allow(File).to receive(:dirname)

      mock_client = double(Object)
      allow(AwsHelper).to receive(:_s3_client).and_return(mock_client)
      mock_response = double(Object)
      allow(mock_client).to receive(:get_object).and_return(mock_response)

      allow(Digest::SHA256).to receive_message_chain('file.base64digest').and_return('dummy-checksum')
      allow(mock_response).to receive(:metadata).and_return('checksum' => 'different-checksum')

      allow(File).to receive(:delete)
      expect {
        AwsHelper.s3_download_object(
          bucket: 'dummy_bucket',
          key: 'dummy-key',
          local_filename: 'dummy-file'
        )
      }      .to raise_exception /Checksum validation for S3 object/
    end

    it 'failed execution - different checksum 2' do
      allow(FileUtils).to receive(:mkdir_p)
      allow(File).to receive(:dirname)

      mock_client = double(Object)
      allow(AwsHelper).to receive(:_s3_client).and_return(mock_client)
      mock_response = double(Object)
      allow(mock_client).to receive(:get_object).and_return(mock_response)

      allow(Digest::SHA256).to receive_message_chain('file.base64digest').and_return('dummy-checksum')
      allow(mock_response).to receive(:metadata).and_return('checksum' => 'different-checksum')

      allow(File).to receive(:delete).and_raise(StandardError)
      expect {
        AwsHelper.s3_download_object(
          bucket: 'dummy_bucket',
          key: 'dummy-key',
          local_filename: 'dummy-file'
        )
      }      .to raise_exception /Checksum validation for S3 object/
    end

    it 'failed execution - Failed to download object' do
      allow(FileUtils).to receive(:mkdir_p)
      allow(File).to receive(:dirname)

      mock_client = double(Object)
      allow(AwsHelper).to receive(:_s3_client).and_return(mock_client)
      mock_response = double(Object)
      allow(mock_client).to receive(:get_object).and_raise(StandardError)
      expect {
        AwsHelper.s3_download_object(
          bucket: 'dummy_bucket',
          key: 'dummy-key',
          local_filename: 'dummy-file'
        )
      }      .to raise_exception /Failed to download object/
    end
  end

  context 's3_download_objects' do
    it 'successful execution' do
      allow(FileUtils).to receive(:mkdir_p)
      allow(File).to receive(:dirname)
      allow(AwsHelper).to receive(:s3_list_objects).and_return(['dummy-key'])
      allow(FileUtils).to receive(:mkpath)
      allow(File).to receive(:dirname)
      allow(AwsHelper).to receive(:s3_download_object)

      expect {
        AwsHelper.s3_download_objects(
          bucket: 'dummy_bucket',
          prefix: 'dummy-prefix'
        )
      }      .not_to raise_exception
    end

    it 'successful execution - failed to download' do
      allow(FileUtils).to receive(:mkdir_p)
      allow(File).to receive(:dirname)
      allow(AwsHelper).to receive(:s3_list_objects).and_return(['dummy-key'])
      allow(FileUtils).to receive(:mkpath)
      allow(File).to receive(:dirname)
      allow(AwsHelper).to receive(:s3_download_object).and_raise(StandardError)

      expect {
        AwsHelper.s3_download_objects(
          bucket: 'dummy_bucket',
          prefix: 'dummy-prefix'
        )
      }.not_to raise_exception
    end

    it 'successful execution - failed to list objects' do
      allow(FileUtils).to receive(:mkdir_p)
      allow(File).to receive(:dirname)
      allow(AwsHelper).to receive(:s3_list_objects).and_raise(StandardError)
      expect {
        AwsHelper.s3_download_objects(
          bucket: 'dummy_bucket',
          prefix: 'dummy-prefix'
        )
      }.not_to raise_exception
    end
  end

  context 's3_delete_object' do
    it 'successful execution' do
      mock_client = double(Object)
      allow(AwsHelper).to receive(:_s3_client).and_return(mock_client)
      mock_response = double(Object)
      allow(mock_client).to receive(:delete_object).and_return(mock_response)
      allow(mock_response).to receive(:version_id)
      expect {
        AwsHelper.s3_delete_object(
          'dummy_bucket',
          'dummy-key'
        )
      }      .not_to raise_exception
    end

    it 'failed with Failed to delete object' do
      mock_client = double(Object)
      allow(AwsHelper).to receive(:_s3_client).and_return(mock_client)
      mock_response = double(Object)
      allow(mock_client).to receive(:delete_object).and_raise(StandardError)
      allow(mock_response).to receive(:version_id)
      expect {
        AwsHelper.s3_delete_object(
          'dummy_bucket',
          'dummy-key'
        )
      }      .to raise_exception /Failed to delete object/
    end

    it 'failed with ArgumentError - bucket - non-string' do
      mock_client = double(Object)
      allow(AwsHelper).to receive(:_s3_client).and_return(mock_client)
      mock_response = double(Object)
      allow(mock_client).to receive(:delete_object).and_raise(StandardError)
      allow(mock_response).to receive(:version_id)
      expect {
        AwsHelper.s3_delete_object(
          1,
          'dummy-key'
        )
      }      .to raise_exception ArgumentError
    end

    it 'failed with ArgumentError - bucket - empty string' do
      mock_client = double(Object)
      allow(AwsHelper).to receive(:_s3_client).and_return(mock_client)
      mock_response = double(Object)
      allow(mock_client).to receive(:delete_object).and_raise(StandardError)
      allow(mock_response).to receive(:version_id)
      expect {
        AwsHelper.s3_delete_object(
          '',
          'dummy-key'
        )
      }      .to raise_exception ArgumentError
    end

    it 'failed with ArgumentError - key - non-string' do
      mock_client = double(Object)
      allow(AwsHelper).to receive(:_s3_client).and_return(mock_client)
      mock_response = double(Object)
      allow(mock_client).to receive(:delete_object).and_raise(StandardError)
      allow(mock_response).to receive(:version_id)
      expect {
        AwsHelper.s3_delete_object(
          'dummy-bucket',
          1
        )
      }      .to raise_exception ArgumentError
    end

    it 'failed with ArgumentError - key - empty string' do
      mock_client = double(Object)
      allow(AwsHelper).to receive(:_s3_client).and_return(mock_client)
      mock_response = double(Object)
      allow(mock_client).to receive(:delete_object).and_raise(StandardError)
      allow(mock_response).to receive(:version_id)
      expect {
        AwsHelper.s3_delete_object(
          'dummy-bucket',
          ''
        )
      }      .to raise_exception ArgumentError
    end
  end

  context 's3_list_objects' do
    it 'successful execution' do
      mock_client = Aws::S3::Client.new(stub_responses: true)
      objects_data = mock_client.stub_data(:list_objects, contents: @mock_data)
      mock_client.stub_responses(:list_objects, objects_data)
      allow(AwsHelper).to receive(:_s3_client).and_return(mock_client)
      objects = AwsHelper.s3_list_objects(
        bucket: 'dummy-bucket',
        prefix: 'dummy-prefix',
      )
      expect(objects).to eql(@mock_data.map { |e| e[:key] })
    end

    it 'fails on exception' do
      mock_client = double(Object)
      allow(AwsHelper).to receive(:_s3_client).and_return(mock_client)
      allow(mock_client).to receive(:list_objects).and_raise(StandardError)
      expect {
        AwsHelper.s3_delete_objects(
          'dummy-bucket',
          'dummy-prefix'
        )
      }      .to raise_exception
    end
  end

  context 's3_delete_objects' do
    it 'successful execution' do
      mock_client = Aws::S3::Client.new(stub_responses: true)
      objects_data = mock_client.stub_data(:list_objects, contents: @mock_data)
      mock_client.stub_responses(:list_objects, objects_data)

      allow(AwsHelper).to receive(:_s3_client).and_return(mock_client)
      allow(mock_client).to receive(:delete_objects)
      expect {
        AwsHelper.s3_delete_objects(
          'dummy-bucket',
          'dummy-prefix'
        )
      }      .not_to raise_exception
    end
  end

  context 's3_copy_object' do
    it 'successful execution' do
      mock_client = double(Object)
      allow(AwsHelper).to receive(:_s3_client).and_return(mock_client)
      mock_response = double(Object)
      allow(mock_client).to receive(:copy_object).and_return(mock_response)
      allow(mock_response).to receive(:version_id)
      expect {
        AwsHelper.s3_copy_object(
          'source-dummy-bucket',
          'source-dummy-prefix',
          'destination-dummy-bucket',
          'destination-dummy-prefix'
        )
      }      .not_to raise_exception
    end

    it 'failed with Failed to copy object' do
      mock_client = double(Object)
      allow(AwsHelper).to receive(:_s3_client).and_return(mock_client)
      mock_response = double(Object)
      allow(mock_client).to receive(:copy_object).and_raise(StandardError)
      expect {
        AwsHelper.s3_copy_object(
          'source-dummy-bucket',
          'source-dummy-prefix',
          'destination-dummy-bucket',
          'destination-dummy-prefix'
        )
      }      .to raise_exception /Failed to copy object/
    end
  end

  context '_s3_upload' do
    it 'successful execution' do
      mock_client = double(Object)
      allow(AwsHelper).to receive(:_s3_client).and_return(mock_client)
      mock_response = double(Object)
      allow(mock_client).to receive(:put_object).and_return(mock_response)
      allow(mock_response).to receive(:version_id)
      expect {
        AwsHelper._s3_upload(
          'dummy-bucket',
          'dummy-prefix',
          'dummy-data',
          'dummy-checksum',
          'dummy-md5'
        )
      }      .not_to raise_exception
    end

    it 'failed with execution' do
      mock_client = double(Object)
      allow(AwsHelper).to receive(:_s3_client).and_return(mock_client)
      mock_response = double(Object)
      allow(mock_client).to receive(:put_object).and_raise(StandardError)
      expect {
        AwsHelper._s3_upload(
          'dummy-bucket',
          'dummy-prefix',
          'dummy-data',
          'dummy-checksum',
          'dummy-md5'
        )
      }      .to raise_exception /Failed to upload/
    end
  end

  context '_s3_client' do
    it 'successful execution - initialize no provisioning or control credentials' do
      allow(Aws::S3::Client).to receive(:new)
      mock_credentials = double(Object)
      allow(AwsHelper).to receive(:_control_credentials)
      allow(AwsHelper).to receive(:sts_get_role_credentials).and_return(mock_credentials)
      expect { AwsHelper._s3_client }.not_to raise_exception
    end

    it 'successful with nil role' do
      allow(Aws::S3::Client).to receive(:new)
      AwsHelper.instance_variable_set(:@s3_role, nil)
      allow(AwsHelper).to receive(:_control_credentials)
      expect { AwsHelper._s3_client }.not_to raise_exception
    end
  end
end
