require 'aws-sdk'

module IamHelper
  def _iam_helper_init()
    @iam_client = nil
  end

  def iam_get_policy(policy_arn: nil)
    begin
      policy = nil
      policy = _iam_client.get_policy(policy_arn: policy_arn)
    rescue => e
      Log.warn "Failed to retrieve IAM Managed Policy (PolicyArn = #{policy_arn}) - #{e}"
    end

    return policy
  end

  def _iam_client
    # Create a new client if it doesn't exist yet
    @client_mutex.synchronize do
      if @iam_client.nil?

        # Creat the CloudFormation client
        Log.debug "Creating a new AWS IAM client"

        # Build the client parameters
        params = {}
        params[:http_proxy] = @proxy unless @proxy.nil?
        params[:region] = @region unless @region.nil?
        params[:retry_limit] = @retry_limit unless @retry_limit.nil?
        credentials = _provisioning_credentials || _control_credentials || nil
        params[:credentials] = credentials unless credentials.nil?

        @iam_client = Aws::IAM::Client.new(params)
      end
    end

    return @iam_client
  end
end
