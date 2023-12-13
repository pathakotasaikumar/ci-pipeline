require 'aws-sdk'

module AmqBrokerHelper
  # Clear object reference to client on initialization
  def _amq_broker_helper_init
    @amq_client = nil
  end

  # Tags Amazon MQ components
  # @param resource_arn [String] Arn of resource to be tagged
  # @param tags[Array] tags to be applied to the resources
  def apply_amq_tags(
    resource_arn:,
    tags:
  )

    Log.debug "Checking if the resource is tagged"

    amq_tags = list_amq_tags(resource_arn: resource_arn)

    if amq_tags.nil? || amq_tags.empty?
      Log.info "Tagging AMQ resource #{resource_arn}"
      params = {
        resource_arn: resource_arn,
        tags: tags,
      }
      begin
        _amq_client.create_tags(**params)
      rescue => e
        Log.warn "Failed to tag resource #{resource_arn}. Failed  with error - #{e}"
        raise "Failed to tag resource #{resource_arn}"
      end
    end
  end

  # Check if the resource is already tagged
  # @param resource_arn [String] Arn of resource to be verified
  # @return tag_details [Object] returns tags applied to the resource
  def list_amq_tags(resource_arn:)
    Log.info "Determining if the resource #{resource_arn} is tagged"
    params = {
      resource_arn: resource_arn
    }

    tag_details = _amq_client.list_tags(params)
    return tag_details.tags
  end

  # Return or initialise a Aws::MQ::Client object
  # @return [Struct] Aws::MQ::Client
  def _amq_client
    # Create a new client if it doesn't exist yet
    @client_mutex.synchronize do
      if @amq_broker_client.nil?

        # Creat the CloudFormation client
        Log.debug "Creating a new Amazon MQ client"

        # Build the client parameters
        params = {}
        params[:http_proxy] = @proxy unless @proxy.nil?
        params[:region] = @region unless @region.nil?
        params[:retry_limit] = @retry_limit unless @retry_limit.nil?
        credentials = _provisioning_credentials || nil
        params[:credentials] = credentials unless credentials.nil?

        @amq_client = Aws::MQ::Client.new(params)
      end
    end

    return @amq_client
  end
end
