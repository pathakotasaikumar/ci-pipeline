$LOAD_PATH.unshift("#{BASE_DIR}/lib/aws_helpers")
require 'dynamodb_helper'

describe 'DynamoDBHelper' do
  context 'dynamodb_query' do
    it 'successful execution' do
      dummy_client = double(Aws::DynamoDB::Client)
      allow(AwsHelper).to receive(:_dynamodb_client).and_return(dummy_client)
      allow(dummy_client).to receive(:query)
      allow(AwsHelper).to receive(:sts_get_role_credentials)
      expect { AwsHelper.dynamodb_query }.not_to raise_exception
    end
  end

  context 'put_item' do
    it 'successful execution' do
      dummy_client = double(Aws::DynamoDB::Client)
      allow(AwsHelper).to receive(:_dynamodb_client).and_return(dummy_client)
      allow(dummy_client).to receive(:put_item)
      allow(AwsHelper).to receive(:sts_get_role_credentials)
      expect { AwsHelper.put_item(table_name: 'test', item: 'test_value') }.not_to raise_exception
    end

    it 'failure execution' do
      dummy_client = double(Aws::DynamoDB::Client)
      allow(AwsHelper).to receive(:_dynamodb_client).and_return(dummy_client)
      allow(dummy_client).to receive(:put_item).and_raise(RuntimeError)
      allow(AwsHelper).to receive(:sts_get_role_credentials)
      expect { AwsHelper.put_item(table_name: 'test', item: 'test_value') }.to raise_exception /Failed to put an item in dynamodb/
    end
  end

  context 'delete_item' do
    it 'successful execution' do
      dummy_client = double(Aws::DynamoDB::Client)
      allow(AwsHelper).to receive(:_dynamodb_client).and_return(dummy_client)
      allow(dummy_client).to receive(:delete_item)
      allow(AwsHelper).to receive(:sts_get_role_credentials)
      expect { AwsHelper.delete_item(table_name: 'test', key: 'test_value') }.not_to raise_exception
    end

    it 'failure execution' do
      dummy_client = double(Aws::DynamoDB::Client)
      allow(AwsHelper).to receive(:_dynamodb_client).and_return(dummy_client)
      allow(dummy_client).to receive(:delete_item).and_raise(RuntimeError)
      allow(AwsHelper).to receive(:sts_get_role_credentials)
      expect { AwsHelper.delete_item(table_name: 'test', key: 'test_value') }.to raise_exception /Failed to delete an item in dynamodb/
    end
  end

  context 'update_item' do
    it 'successful execution' do
      dummy_client = double(Aws::DynamoDB::Client)
      allow(AwsHelper).to receive(:_dynamodb_client).and_return(dummy_client)
      allow(dummy_client).to receive(:update_item)
      allow(AwsHelper).to receive(:sts_get_role_credentials)
      expect {
        AwsHelper.update_item(
          table_name: 'test',
          key: 'test_value'
        )
      }      .not_to raise_exception
    end

    it 'failure execution' do
      dummy_client = double(Aws::DynamoDB::Client)
      allow(AwsHelper).to receive(:_dynamodb_client).and_return(dummy_client)
      allow(dummy_client).to receive(:update_item).and_raise(RuntimeError)
      allow(AwsHelper).to receive(:sts_get_role_credentials)
      expect {
        AwsHelper.update_item(
          table_name: 'test',
          key: 'test_value'
        )
      }      .to raise_exception /Failed to update an item in dynamodb/
    end
  end

  context '_dynamodb_client' do
    it 'successful execution - initialize no provisioning or control credentials' do
      allow(Aws::DynamoDB::Client).to receive(:new)
      allow(AwsHelper).to receive(:_control_credentials)
      expect { AwsHelper._dynamodb_client }.not_to raise_exception
    end

    it 'successful execution - initialize with provisioning credentials' do
      allow(Aws::DynamoDB::Client).to receive(:new)
      allow(AwsHelper).to receive(:_control_credentials)
      expect { AwsHelper._dynamodb_client }.not_to raise_exception
    end

    it 'successful execution - initialize with control credentials' do
      allow(Aws::DynamoDB::Client).to receive(:new)
      mock_credentials = double(Object)
      allow(AwsHelper).to receive(:_control_credentials).and_return(mock_credentials)
      expect { AwsHelper._dynamodb_client }.not_to raise_exception
    end
  end
end
