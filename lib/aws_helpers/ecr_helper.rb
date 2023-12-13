require 'aws-sdk'
require 'base64'

module EcrHelper

  def _ecr_helper_init
    @ecr_client = nil
  end

  def ecr_get_authorisation_token
    response = _ecr_client.get_authorization_token
    encoded_auth_token = response.authorization_data.first.authorization_token
    auth_token = Base64.decode64(encoded_auth_token).sub("AWS:","")
    return auth_token
  end

  def ecr_repository_exists?(repository_name)
    resp = _ecr_client.describe_repositories(repository_names: [repository_name])
    Log.info("ECR Repository #{repository_name} exists")
    return true
  rescue Aws::ECR::Errors::RepositoryNotFoundException => e
    Log.info("ECR Repository #{repository_name} not found")
    return false
  end

  def ecr_set_repository_policy(
    repository_name:,
    policy_text:
  )
    _ecr_client.set_repository_policy(
      repository_name: repository_name,
      policy_text: policy_text
    )
  end

  def ecr_create_repository(
    repository_name:,
    image_tag_mutability: "MUTABLE",
    tags: {}
  )

    _ecr_client.create_repository({
      repository_name: repository_name,
      image_tag_mutability: image_tag_mutability,
      tags: tags
    })

  end

  def ecr_put_image_scanning_configuration(
    repository_name:,
    scan_on_push: true
  )
    _ecr_client.put_image_scanning_configuration(
      repository_name: repository_name,
      image_scanning_configuration: {
        scan_on_push: scan_on_push
      }
    )

  end

  def _ecr_client
    # Create a new client if it doesn't exist yet
    @client_mutex.synchronize do
      if @ecr_client.nil?

        # Creat the CloudFormation client
        Log.debug "Creating a new AWS ECR client"

        # Build the client parameters
        params = {}
        params[:http_proxy] = @proxy unless @proxy.nil?
        params[:region] = @region unless @region.nil?
        params[:retry_limit] = @retry_limit unless @retry_limit.nil?
        credentials = _control_credentials || nil
        params[:credentials] = credentials unless credentials.nil?

        @ecr_client = Aws::ECR::Client.new(params)
      end
    end

    return @ecr_client
  end
end