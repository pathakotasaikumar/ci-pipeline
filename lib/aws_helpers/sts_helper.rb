require 'aws-sdk'

module StsHelper
  def _sts_helper_init(control_role: nil, provisioning_role: nil)
    @sts_base_client = nil
    @sts_control_client = nil

    @sts_control_role = control_role
    @sts_provisioning_role = provisioning_role

    @sts_control_credentials = nil
    @sts_provisioning_credentials = nil
  end

  def sts_get_role_credentials(role_arn, sts_client = :auto)
    sts_client = if sts_client == :auto
                   _sts_control_client || _sts_base_client
                 elsif sts_client == :control
                   _sts_control_client
                 else
                   _sts_base_client
                 end

    Log.debug "Retrieving credentials for role #{role_arn.inspect}"
    credentials = Aws::AssumeRoleCredentials.new(
      client: sts_client,
      role_arn: role_arn,
      role_session_name: "#{Defaults.sections[:qda]}-#{Defaults.sections[:env][0]}-#{Defaults.sections[:as]}-session"
    )

    return credentials
  end

  def _control_credentials
    return nil if @sts_control_role.nil?

    if @sts_control_credentials.nil?
      @sts_control_credentials = sts_get_role_credentials(@sts_control_role, :base)
    end

    return @sts_control_credentials
  end

  def _provisioning_credentials
    # No provisioning role was specified - don't return provisioning credentials
    return nil if @sts_provisioning_role.nil?

    if @sts_provisioning_credentials.nil?
      @sts_provisioning_credentials = sts_get_role_credentials(@sts_provisioning_role)
    end

    return @sts_provisioning_credentials
  end

  def _sts_base_client
    if @sts_base_client.nil?
      Log.debug "Creating new AWS STS client with base credentials"
      params = {}
      params[:http_proxy] = @proxy unless @proxy.nil?
      params[:region] = @region unless @region.nil?
      params[:retry_limit] = @retry_limit unless @retry_limit.nil?
      @sts_base_client = Aws::STS::Client.new(params)
    end

    return @sts_base_client
  end

  def _sts_control_client
    # No control role was specified - don't return a control STS client
    return nil if @sts_control_role.nil?

    if @sts_control_client.nil?
      # Create an STS client with the control role credentials
      Log.debug "Creating new AWS STS client with credentials for role #{@sts_control_role.inspect}"
      params = {}
      params[:http_proxy] = @proxy unless @proxy.nil?
      params[:region] = @region unless @region.nil?
      params[:retry_limit] = @retry_limit unless @retry_limit.nil?
      params[:credentials] = _control_credentials

      @sts_control_client = Aws::STS::Client.new(params)
    end

    return @sts_control_client
  end
end
