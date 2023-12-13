module SsmHelper
  def _ssm_helper_init
    @ssm_client = nil
    @ssm_provision_client = nil
  end

  # Stars execution of a step function state machine
  # @param name [String]
  # @return [String] Parameter value
  def ssm_get_parameter(
    name:,
    with_decryption: false
  )
    params = {
      names: [name],
      with_decryption: with_decryption
    }

    response = _ssm_client.get_parameters(params)
    response.parameters.first.value unless response.nil? || response.empty?
  rescue => e
    raise "Unable to query parameter #{name} - #{e}"
  end

  def ssm_get_provision_parameter(
    name:,
    with_decryption: false
  )
    params = {
      names: [name],
      with_decryption: with_decryption
    }

    response = _ssm_provision_client.get_parameters(params)
    response.parameters.first.value unless response.nil? || response.empty?
  rescue => e
    raise "Unable to query parameter #{name} - #{e}"
  end



  # Returns a list of parameters based on hierarchical path
  # @param path [String] Slash (/) separated path
  # @param recursive [Bool] or not
  # @param assume_provision_client [Bool] or not - parameter to assume the right client
  def ssm_get_parameters_by_path(
    path:,
    recursive: true,
    with_decryption: false,
    assume_provision_client: false
  )

    parameters = []
    next_token = nil

    client = if assume_provision_client
               Log.debug "Using assumed provision client"
               _ssm_provision_client
             else
               Log.debug "Using control provision client"
               _ssm_client
             end

    loop do
      Log.debug "Fetching params under path: #{path}, recursive: #{recursive}, with_decryption: #{with_decryption}"

      response = client.get_parameters_by_path(
        path: path,
        recursive: recursive,
        with_decryption: with_decryption,
        next_token: next_token
      )

      Log.debug "fetched #{response.parameters.count} params"

      parameters += response.parameters
      next_token = response.next_token

      if next_token.nil?
        Log.debug "next_token is null, finished"
        break
      else
        Log.debug "next_token is not null, continue"
      end
    end

    return parameters
  end

  # Returns an instance of AWS::States::Client
  # @return [Object] AWS::States::Client
  def _ssm_client
    # Create a new client if it doesn't exist yet
    @client_mutex.synchronize do
      if @ssm_client.nil?
        # Build the client parameters
        params = {}
        params[:http_proxy] = @proxy unless @proxy.nil?
        params[:region] = @region unless @region.nil?
        params[:retry_limit] = @retry_limit unless @retry_limit.nil?
        credentials = _control_credentials || nil
        params[:credentials] = credentials unless credentials.nil?

        @ssm_client = Aws::SSM::Client.new(params)
      end
    end

    @ssm_client
  end

  # Returns an instance of AWS::States::Client
  # @return [Object] AWS::States::Client
  def _ssm_provision_client
    # Create a new client if it doesn't exist yet
    @client_mutex.synchronize do
      if @ssm_provision_client.nil?
        # Build the client parameters
        params = {}
        params[:http_proxy] = @proxy unless @proxy.nil?
        params[:region] = @region unless @region.nil?
        params[:retry_limit] = @retry_limit unless @retry_limit.nil?
        credentials = _provisioning_credentials || nil
        params[:credentials] = credentials unless credentials.nil?

        @ssm_provision_client = Aws::SSM::Client.new(params)
      end
    end

    @ssm_provision_client
  end
end
