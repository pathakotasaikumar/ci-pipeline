require 'aws-sdk'

module ElastiCacheHelper
  def _elasticache_helper_init
    @elasticache_client = nil
  end

  def elasticache_get_replication_group_clusters(replication_group_id)
    Log.debug "Retrieving cache clusters for replication group #{replication_group_id.inspect}"
    response = _elasticache_client.describe_replication_groups(replication_group_id: replication_group_id)

    return [] if response.replication_groups.empty?

    return response.replication_groups[0].member_clusters
  end

  def elasticache_set_tags(resource_ids, tags)
    resource_ids.each do |resource_id|
      Log.debug "Setting tags for ElastiCache resource #{resource_id.inspect}"
      _elasticache_client.add_tags_to_resource(
        resource_name: resource_id,
        tags: tags
      )
    end
  end

  def _elasticache_client
    # Create a new client if it doesn't exist yet
    @client_mutex.synchronize do
      if @elasticache_client.nil?

        # Creat the CloudFormation client
        Log.debug "Creating a new AWS ElastiCache client"

        # Build the client parameters
        params = {}
        params[:http_proxy] = @proxy unless @proxy.nil?
        params[:region] = @region unless @region.nil?
        params[:retry_limit] = @retry_limit unless @retry_limit.nil?
        credentials = _provisioning_credentials || _control_credentials || nil
        params[:credentials] = credentials unless credentials.nil?

        @elasticache_client = Aws::ElastiCache::Client.new(params)
      end
    end

    return @elasticache_client
  end
end
