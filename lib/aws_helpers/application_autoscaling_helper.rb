require 'aws-sdk'

module ApplicationAutoscalingHelper
  def _application_autoscaling_helper_init
    @application_autoscaling_client = nil
  end

  def scalable_target_wait_for_capacity(
    service_namespace:nil,
    scalable_target_id:nil,
    min_capacity: nil,
    max_capacity: nil,
    max_attempts: 60,
    delay: 30
  )
    Log.debug "running scalable_target_wait_for_capacity with these values-> service_namespace: #{service_namespace}, resource_ids: #{scalable_target_id}, min_capacity: #{min_capacity}, max_capacity: #{max_capacity}"      

    if !scalable_target_id
      Log.warn "Skipping wait for scalable target to reach capacity - no scalable_target_id was provided"
      return false
    end

    if !service_namespace
      Log.warn "Skipping wait for scalable target to reach capacity - no service_namespace was provided"
      return false
    end

    if !min_capacity and !max_capacity
      Log.warn "Skipping wait for scalable target to reach capacity - no min or max size was provided"
      return false
    end

    # Minimum of 1 attempt
    max_attempts = [1, max_attempts].max

    (1..max_attempts).each do |attempt|
      Log.output "attemp: #{attempt} of #{max_attempts}"
      
      resp = _application_autoscaling_client.describe_scalable_targets(
        service_namespace: service_namespace,
        resource_ids: [scalable_target_id],
        max_results: 1,
      )
      
      # Scalable target doesn't exist
      if resp.scalable_targets.nil? or resp.scalable_targets.empty?
        raise "scalable target #{scalable_target_id} does not exist"
      end

      resp = _application_autoscaling_client.describe_scaling_activities(
        service_namespace: service_namespace,
        resource_id: scalable_target_id,
      )
      
      # Scalable target has not been changed
      if resp.scaling_activities.nil? or resp.scaling_activities.empty?
        return true
      end

      status_code = resp.scaling_activities[0].status_code
      Log.output "status_code of the scaling_activities for scalable target #{scalable_target_id} is #{status_code}"

      return true if (status_code=="Successful")
      
      Log.output "sleeping for #{delay} seconds"
      sleep(delay) if attempt != max_attempts
    end

    raise "Timed out waiting to reach target capacity"
  end

  def _application_autoscaling_client
    # Create a new client if it doesn't exist yet
    @client_mutex.synchronize do
      if @application_autoscaling_client.nil?

        # Creat the CloudFormation client
        Log.debug "Creating a new AWS Autoscaling client"

        # Build the client parameters
        params = {}
        params[:http_proxy] = @proxy unless @proxy.nil?
        params[:region] = @region unless @region.nil?
        params[:retry_limit] = @retry_limit unless @retry_limit.nil?
        credentials = _provisioning_credentials || _control_credentials || nil
        params[:credentials] = credentials unless credentials.nil?

        @application_autoscaling_client = Aws::ApplicationAutoScaling::Client.new(params)
      end
    end

    return @application_autoscaling_client
  end
end
