require 'aws-sdk'

# Module provides wrappers for aws-sdk for CodeDeploy client

module CodeDeployHelper
  def _codedeploy_helper_init
    @codedeploy_client = nil
  end

  def _codedeploy_client
    # Create a new client if it doesn't exist yet
    @client_mutex.synchronize do
      if @codedeploy_client.nil?

        Log.debug "Creating a new AWS CodeDeploy client"

        # Build the client parameters
        params = {}
        params[:http_proxy] = @proxy unless @proxy.nil?
        params[:region] = @region unless @region.nil?
        params[:retry_limit] = @retry_limit unless @retry_limit.nil?

        if _provisioning_credentials
          # We have specific provisioning credentials to use
          params[:credentials] = _provisioning_credentials
        elsif _control_credentials
          # No provisioning credentials but we do have control credentials to use
          params[:credentials] = _control_credentials
        end

        @codedeploy_client = Aws::CodeDeploy::Client.new(params)
      end
    end

    @codedeploy_client
  end

  def create_codedeploy_deployment(payload:)
    responce = _codedeploy_client.create_deployment(payload)
    deployment_id = responce.deployment_id

    deployment_id
  end

  def wait_codedeploy_deployment(deployment_id:, poll_time_in_sec: 10, expected_deploy_statuses: ["Succeeded", "Failed"])
    deployment_status = nil
    is_expected_status = false

    while !is_expected_status do
      Log.debug "Polling deployment status for deployment_id: #{deployment_id}"

      status = get_deployment_status(deployment_id: deployment_id)

      is_expected_status = expected_deploy_statuses.include?(status)
      Log.debug " - deployment_id: #{deployment_id} status: #{status} is_expected_status: #{is_expected_status} poll_time_in_sec: #{poll_time_in_sec}"

      if !is_expected_status
        Log.debug " - deployment_id: #{deployment_id}, sleeping #{poll_time_in_sec} sec"
        sleep poll_time_in_sec
      end

    end
  end

  def get_deployment_status(deployment_id:)
    response = _codedeploy_client.get_deployment(deployment_id: deployment_id)
    status = response.deployment_info.status
  end

  def fetch_codedeploy_instancies(deployment_id:)
    result = []

    Log.debug "Fetching deployment instancies for deployment ID: #{deployment_id}"
    deployment_instances = _codedeploy_client.list_deployment_instances({
      deployment_id: deployment_id
    }).instances_list

    deployment_instances.each do |deployment_instance_id|
      Log.debug "Fetching logs for deployment instance: #{deployment_instance_id}"

      result << _codedeploy_client.get_deployment_instance({
        deployment_id: deployment_id,
        instance_id: deployment_instance_id
      })
    end

    result
  end
end
