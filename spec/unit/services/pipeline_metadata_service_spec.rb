$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib/services"))
require 'pipeline_metadata_service.rb'

RSpec.describe 'PipelineMetadataService' do
  context 'save_metadata' do
    it 'successful put item execution' do
      dummy_client = double(Aws::DynamoDB::Client)
      allow(AwsHelper).to receive(:_dynamodb_client).and_return(dummy_client)
      allow(dummy_client).to receive(:update_item)
      allow(AwsHelper).to receive(:sts_get_role_credentials)
      allow(Defaults).to receive(:pipeline_build_metadata_dynamodb_table_name).and_return('table_name')

      dynamodb_query_mock_response = double(Object)
      allow(PipelineMetadataService).to receive(:_construct_context_path).and_return('ams01-c031-01-dev-test-Release')

      allow(AwsHelper).to receive(:dynamodb_query).and_return(dynamodb_query_mock_response)
      allow(dynamodb_query_mock_response).to receive_message_chain('items.empty?').and_return(true)
      allow(AwsHelper).to receive(:put_item)
      expect {
        PipelineMetadataService.save_metadata(
          context_name: ['ams01', 'c031', '01', 'dev', 'test', 'Release'],
          context: { 'test' => 'test' }
        )
      }      .not_to raise_exception
    end

    it 'failure put item execution' do
      dummy_client = double(Aws::DynamoDB::Client)
      allow(AwsHelper).to receive(:_dynamodb_client).and_return(dummy_client)
      allow(dummy_client).to receive(:update_item)
      allow(AwsHelper).to receive(:sts_get_role_credentials)
      allow(Defaults).to receive(:pipeline_build_metadata_dynamodb_table_name).and_return('table_name')
      allow(PipelineMetadataService).to receive(:_construct_context_path).and_return('ams01-c031-01-dev-test-Release')
      dynamodb_query_mock_response = double(Object)
      allow(AwsHelper).to receive(:dynamodb_query).and_return(dynamodb_query_mock_response)
      allow(dynamodb_query_mock_response).to receive_message_chain('items.empty?').and_return(true)
      allow(AwsHelper).to receive(:put_item).and_raise(RuntimeError)
      expect {
        PipelineMetadataService.save_metadata(
          context_name: ['ams01', 'c031', '01', 'dev', 'test', 'Release'],
          context: { 'test' => 'test' }
        )
      }      .to raise_exception /Failed to save the context in dynamodb/
    end

    it 'successful update item execution' do
      dummy_client = double(Aws::DynamoDB::Client)
      allow(AwsHelper).to receive(:_dynamodb_client).and_return(dummy_client)
      allow(dummy_client).to receive(:update_item)
      allow(AwsHelper).to receive(:sts_get_role_credentials)
      allow(Defaults).to receive(:pipeline_build_metadata_dynamodb_table_name).and_return('table_name')
      allow(PipelineMetadataService).to receive(:_construct_context_path).and_return('ams01-c031-01-dev-test-Release')
      dynamodb_query_mock_response = double(Object)
      allow(AwsHelper).to receive(:dynamodb_query).and_return(dynamodb_query_mock_response)
      allow(dynamodb_query_mock_response).to receive_message_chain('items.empty?').and_return(false)
      allow(AwsHelper).to receive(:update_item)
      expect {
        PipelineMetadataService.save_metadata(
          context_name: ['ams01', 'c031', '01', 'dev', 'test', 'Release'],
          context: { 'test' => 'test' }
        )
      }      .not_to raise_exception
    end

    it 'failure update item execution' do
      dummy_client = double(Aws::DynamoDB::Client)
      allow(AwsHelper).to receive(:_dynamodb_client).and_return(dummy_client)
      allow(dummy_client).to receive(:update_item)
      allow(AwsHelper).to receive(:sts_get_role_credentials)
      allow(Defaults).to receive(:pipeline_build_metadata_dynamodb_table_name).and_return('table_name')
      allow(PipelineMetadataService).to receive(:_construct_context_path).and_return('ams01-c031-01-dev-test-Release')
      dynamodb_query_mock_response = double(Object)
      allow(AwsHelper).to receive(:dynamodb_query).and_return(dynamodb_query_mock_response)
      allow(dynamodb_query_mock_response).to receive_message_chain('items.empty?').and_return(false)
      allow(AwsHelper).to receive(:update_item).and_raise(RuntimeError)
      expect {
        PipelineMetadataService.save_metadata(
          context_name: ['ams01', 'c031', '01', 'dev', 'test', 'Release'],
          context: { 'test' => 'test' }
        )
      }      .to raise_exception /Failed to save the context in dynamodb/
    end

    it 'successful delete item execution' do
      dummy_client = double(Aws::DynamoDB::Client)
      allow(AwsHelper).to receive(:_dynamodb_client).and_return(dummy_client)
      allow(dummy_client).to receive(:update_item)
      allow(AwsHelper).to receive(:sts_get_role_credentials)
      allow(Defaults).to receive(:pipeline_build_metadata_dynamodb_table_name).and_return('table_name')
      allow(PipelineMetadataService).to receive(:_construct_context_path).and_return('ams01-c031-01-dev-test-Release')
      dynamodb_query_mock_response = double(Object)
      allow(AwsHelper).to receive(:dynamodb_query).and_return(dynamodb_query_mock_response)
      allow(dynamodb_query_mock_response).to receive_message_chain('items.empty?').and_return(false)
      allow(AwsHelper).to receive(:delete_item)
      expect {
        PipelineMetadataService.save_metadata(
          context_name: ['ams01', 'c031', '01', 'dev', 'test', 'Release'],
          context: nil
        )
      }      .not_to raise_exception
    end

    it 'failure delete item execution' do
      dummy_client = double(Aws::DynamoDB::Client)
      allow(AwsHelper).to receive(:_dynamodb_client).and_return(dummy_client)
      allow(dummy_client).to receive(:update_item)
      allow(AwsHelper).to receive(:sts_get_role_credentials)
      allow(Defaults).to receive(:pipeline_build_metadata_dynamodb_table_name).and_return('table_name')
      allow(PipelineMetadataService).to receive(:_construct_context_path).and_return('ams01-c031-01-dev-test-Release')
      dynamodb_query_mock_response = double(Object)
      allow(AwsHelper).to receive(:dynamodb_query).and_return(dynamodb_query_mock_response)
      allow(dynamodb_query_mock_response).to receive_message_chain('items.empty?').and_return(false)
      allow(AwsHelper).to receive(:delete_item).and_raise(RuntimeError)
      expect {
        PipelineMetadataService.save_metadata(
          context_name: ['ams01', 'c031', '01', 'dev', 'test', 'Release'],
          context: nil
        )
      }      .to raise_exception /Failed to save the context in dynamodb/
    end
  end

  context '_construct_context_path' do
    it 'successful construction' do
      expect(PipelineMetadataService.send(:_construct_context_path, ['ams01', 'c031', '01', 'dev', 'test', 'release'])).to eq('ams01-c031-01-dev-test-release')
    end
  end

  context 'load_metadata' do
    it 'successfully load release context' do
      allow(Context).to receive_message_chain('persist.release_path').and_return(['ams01', 'c031', '01', 'dev', 'test', 'release'])
      allow(Defaults).to receive(:pipeline_build_metadata_dynamodb_table_name)
      dynamodb_query_mock_response = double(Object)
      allow(AwsHelper).to receive(:dynamodb_query).and_return(dynamodb_query_mock_response)
      allow(dynamodb_query_mock_response).to receive_message_chain('items.empty?').and_return(false)
      allow(dynamodb_query_mock_response).to receive('items').and_return([{ 'context' => { 'ReleasedBuildNumber' => '30' } }])
      expect(PipelineMetadataService.load_metadata).to eq("30")
    end

    it 'return nil if not able to load release context' do
      allow(Context).to receive_message_chain('persist.release_path').and_return(['ams01', 'c031', '01', 'dev', 'test', 'release'])
      allow(Defaults).to receive(:pipeline_build_metadata_dynamodb_table_name)
      dynamodb_query_mock_response = double(Object)
      allow(AwsHelper).to receive(:dynamodb_query).and_return(dynamodb_query_mock_response)
      allow(dynamodb_query_mock_response).to receive_message_chain('items.empty?').and_return(true)
      expect(PipelineMetadataService.load_metadata).to eq(nil)
    end
  end
end
