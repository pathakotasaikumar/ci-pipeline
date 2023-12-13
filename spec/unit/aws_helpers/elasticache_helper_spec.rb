$LOAD_PATH.unshift("#{BASE_DIR}/lib/aws_helpers")
require 'elasticache_helper'

describe 'ElastiCacheHelper' do
  context 'elasticache_get_replication_group_clusters' do
    it 'successful execution' do
      dummy_client = double(Aws::ElastiCache::Client)
      mock_response = double(Object)
      mock_replication_group = double(Object)
      allow(AwsHelper).to receive(:_elasticache_client).and_return(dummy_client)
      allow(dummy_client).to receive(:describe_replication_groups).and_return(mock_response)
      allow(mock_response).to receive(:replication_groups).and_return([mock_replication_group])
      allow(mock_replication_group).to receive(:member_clusters).and_return('dummy-clusters')
      expect {
        AwsHelper.elasticache_get_replication_group_clusters('dummy_replication_group_id')
      }.not_to raise_exception
    end
  end

  context 'elasticache_set_tags' do
    it 'successful execution' do
      dummy_client = double(Aws::ElastiCache::Client)
      allow(AwsHelper).to receive(:_elasticache_client).and_return(dummy_client)
      allow(dummy_client).to receive(:add_tags_to_resource)
      expect {
        AwsHelper.elasticache_set_tags(['dummy-resource-id'], ['dummy-tags'])
      }.not_to raise_exception
    end
  end

  context '_elasticache_client' do
    it 'successful execution - initialize no provisioning or control credentials' do
      allow(Aws::ElastiCache::Client).to receive(:new)
      allow(AwsHelper).to receive(:_provisioning_credentials)
      allow(AwsHelper).to receive(:_control_credentials)
      expect { AwsHelper._elasticache_client }.not_to raise_exception
    end

    it 'successful execution - initialize with provisioning credentials' do
      allow(Aws::ElastiCache::Client).to receive(:new)
      mock_credentials = double(Object)
      allow(AwsHelper).to receive(:_provisioning_credentials).and_return(mock_credentials)
      allow(AwsHelper).to receive(:_control_credentials)
      expect { AwsHelper._elasticache_client }.not_to raise_exception
    end

    it 'successful execution - initialize with control credentials' do
      allow(Aws::ElastiCache::Client).to receive(:new)
      mock_credentials = double(Object)
      allow(AwsHelper).to receive(:_provisioning_credentials)
      allow(AwsHelper).to receive(:_control_credentials).and_return(mock_credentials)
      expect { AwsHelper._elasticache_client }.not_to raise_exception
    end
  end
end
