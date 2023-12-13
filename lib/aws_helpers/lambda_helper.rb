require 'aws-sdk'

module LambdaHelper
  # Clear object reference to client on initialisation
  def _lambda_helper_init
    @lambda_client = nil
  end

  # Invokes a lambda function synchronously
  # @param function_name [String] Name of the target lambda function
  # @param payload [Hash] Function input
  # @param log_type [String] Return function logs as type (Tail)
  # @return [Object] Response object
  def lambda_invoke(function_name:, payload: nil, log_type: nil)
    params = {
      function_name: function_name
    }
    params[:payload] = payload unless payload.nil? || payload.empty?
    params[:log_type] = log_type unless log_type.nil? || log_type.empty?

    _lambda_client.invoke(**params)
  rescue => e
    raise "Unable to invoke the lambda function #{function_name} - #{e}"
  end

  # Function to add permission to the lambda function
  # @param function_name [String] Name of the target lambda function
  # @param action [String] Action
  # @param principal [String]
  # @param statement_id [String]
  # @param source_account [String]
  # @param source_arn [String]
  # @return [Object] Response object
  def lambda_add_permission(
    function_name:,
    principal:,
    action:,
    statement_id:,
    source_account: nil,
    source_arn: nil,
    qualifier: nil
  )

    params = {
      function_name: function_name,
      principal: principal,
      action: action,
      statement_id: statement_id
    }
    params[:source_account] = source_account unless source_account.nil? || source_account.empty?
    params[:source_arn] = source_arn unless source_arn.nil? || source_arn.empty?
    params[:qualifier] = qualifier unless qualifier.nil? || qualifier.empty?

    _lambda_client.add_permission(**params)
  rescue => e
    raise "Unable to execute lambda add permission for function #{function_name} - #{e}"
  end

  # Function to get the policy attached with the lambda
  # @param function_name [String] Name of the target lambda function
  # @return [Object] Response object
  def lambda_get_policy(function_name: nil, qualifier: nil)
    params = {
      function_name: function_name
    }
    params[:qualifier] = qualifier unless qualifier.nil? || qualifier.empty?

    policy = _lambda_client.get_policy(**params)
    return policy
  rescue Aws::Lambda::Errors::ResourceNotFoundException => e
    Log.debug "Unable to retrieve the policy for the lambda function #{function_name} - #{e}"
    return {}
  rescue => e
    raise "Failed to retrieve the policy for the lambda function #{function_name} - #{e}"
  end

  # Returns lambda versions for a given function
  # @param function_name [String] Name of the lambda function
  # @return [Array] List of lambda versions
  def lambda_versions(function_name:)
    response = _lambda_client.list_versions_by_function(
      function_name: function_name
    )
    response.nil? ? [] : response.versions
  rescue Aws::Lambda::Errors::ResourceNotFoundException => e
    Log.debug "Unable to find function #{function_name} - #{e}"
  rescue => e
    raise "Unable to query versions for function #{function_name} - #{e}"
  end

  # Return or initialise a AWS::Lambda::Client object
  # @return [Struct] AWS::Lambda::Client
  def _lambda_client
    # Create a new client if it doesn't exist yet
    @client_mutex.synchronize do
      if @lambda_client.nil?
        # Build the client parameters
        params = {}
        params[:http_proxy] = @proxy unless @proxy.nil?
        params[:region] = @region unless @region.nil?
        params[:retry_limit] = @retry_limit unless @retry_limit.nil?
        credentials = _provisioning_credentials || _control_credentials || nil
        params[:credentials] = credentials unless credentials.nil?

        @lambda_client = Aws::Lambda::Client.new(**params)
      end
    end

    return @lambda_client
  end
end
