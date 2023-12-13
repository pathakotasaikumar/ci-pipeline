require 'aws-sdk'

module Route53Helper
  # Clear object reference to client on initialisation
  def _route53_helper_init
    @route53_client = nil
  end

  # Check the route53 health check status
  # @param healthcheckid [String]
  # @param status [String]
  # @param delay [String]
  # @param max_attempts [String]
  def _route53_check_health_status(
    healthcheckid:,
    status:,
    delay: 30,
    max_attempts: 30
  )

    max_attempts = [1, max_attempts].max

    (1..max_attempts).each do |attempt|
      resp = _route53_client.get_health_check_status(
        health_check_id: healthcheckid,
      )

      status_message = resp.health_check_observations.first.status_report.status

      current_status =  case status_message.downcase
                        when /^success/
                          "Healthy"
                        when /^failure/
                          "UnHealthy"
                        else
                          "Unknown"
                        end

      Log.debug "The current status of Health check is : #{current_status} expected is #{status.inspect}"

      # Return if current_status is available
      return true if current_status.downcase =~ /#{status.downcase}/i

      sleep(delay) if attempt != max_attempts
    end

    raise "Timed out waiting for Health check to #{status}"
  end

  # Retrieve a Route53 client
  def _route53_client
    # Create a new client if it doesn't exist yet
    @client_mutex.synchronize do
      if @route53_client.nil?

        # Creat the Route53 client
        Log.debug "Creating a new Route 53 client"

        # Build the client parameters
        params = {}
        params[:http_proxy] = @proxy unless @proxy.nil?
        params[:region] = @region unless @region.nil?
        params[:retry_limit] = @retry_limit unless @retry_limit.nil?
        credentials = _provisioning_credentials || _control_credentials || nil
        params[:credentials] = credentials unless credentials.nil?

        @route53_client = Aws::Route53::Client.new(params)
      end
    end

    return @route53_client
  end
end
