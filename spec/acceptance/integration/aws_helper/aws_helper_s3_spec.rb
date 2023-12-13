$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib/util"))
require 'yaml'

RSpec.describe AwsHelperClass do
  before(:all) {
    @aws_helper = AwsHelper

    # S3 method tests
    @bucket = ENV['dev_bucket'] || 'cf-core-pipeline-dev'
    @test_string = 'This is test data or the aws_helper_spec tests. 1234567890 !@#$%^&*() abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLMNOPQRSTUVWXYZ `~[]{}/?=+-_\'"\\,<.>|'
    @test_file_path = "#{TEST_DATA_DIR}/test_file.gz"
    @s3_state = {}
  }

  context 'S3 method' do
    it '.s3_put_object puts an object in a bucket' do
      expect {
        @s3_state[:put_data_version_id] = @aws_helper.s3_put_object(@bucket, 'test_data', @test_string)
        Log.info "Uploaded test data object, version_id = #{@s3_state[:put_data_version_id].inspect}"
      }.to_not raise_error
    end

    it '.s3_get_object retrieves an uploaded object from a bucket' do
      expect {
        @s3_state[:get_data], @s3_state[:get_data_version_id] = @aws_helper.s3_get_object(@bucket, 'test_data', @s3_state[:put_data_version_id])
        Log.info "Retrieved test data, version_id: #{@s3_state[:get_data_version_id].inspect}"
      }.to_not raise_error

      expect(@s3_state[:get_data]).to eq(@test_string)
      expect(@s3_state[:get_data_version_id]).to eq(@s3_state[:put_data_version_id])
    end

    it '.s3_delete_object deletes an uploaded object from a bucket' do
      expect {
        @aws_helper.s3_delete_object(@bucket, 'test_data', @s3_state[:put_data_version_id])
      }.to_not raise_error
    end

    it '.s3_upload_file uploads a file to a bucket' do
      expect {
        @s3_state[:put_file_version_id] = @aws_helper.s3_upload_file(@bucket, 'test_file', @test_file_path)
        Log.info "Uploaded test file, version_id = #{@s3_state[:put_file_version_id].inspect}"
      }.to_not raise_error
    end

    it '.s3_get_object retrieves an uploaded file from a bucket' do
      expect {
        @s3_state[:get_file_contents], @s3_state[:get_file_version_id] = @aws_helper.s3_get_object(@bucket, 'test_file', @s3_state[:put_file_version_id])
        Log.info "Retrieved test file contents, version_id = #{@s3_state[:get_file_version_id].inspect}"
      }.to_not raise_error

      file_contents = File.read(@test_file_path)
      expect(@s3_state[:get_file_contents]).to eq(file_contents)
      expect(@s3_state[:get_file_version_id]).to eq(@s3_state[:put_file_version_id])
    end

    it '.s3_delete_object deletes an uploaded file from a bucket' do
      expect {
        @aws_helper.s3_delete_object(@bucket, 'test_file', @s3_state[:put_file_version_id])
      }.to_not raise_error
    end
  end
end
