require 'aws-sdk'

module AutoscalingHelper
  def _autoscaling_helper_init
    @autoscaling_client = nil
  end

  def describe_scaling_activities(
    autoscaling_group_name: nil
  )
    _autoscaling_client.describe_scaling_activities({
      auto_scaling_group_name: autoscaling_group_name
    })
  end

  def autoscaling_remove_instance_protection(
    autoscaling_group_name: nil
  )

    params = {}
    params[:auto_scaling_group_name] = autoscaling_group_name
    params[:protected_from_scale_in] = false
    params[:instance_ids] = []

    describe_auto_scaling_response = _autoscaling_client.describe_auto_scaling_groups(
      auto_scaling_group_names: [autoscaling_group_name],
      max_records: 1,
    )

    # ASG doesn't exist
    if describe_auto_scaling_response.auto_scaling_groups.nil? or describe_auto_scaling_response.auto_scaling_groups.empty?
      raise "ASG #{autoscaling_group_name.inspect} does not exist"
    end

    instances = describe_auto_scaling_response.auto_scaling_groups[0].instances

    # Count any instances that have instance protection enabled
    protected_count = instances.select { |instance| instance.protected_from_scale_in == true }.size

    Log.debug "ASG #{autoscaling_group_name.inspect} has #{protected_count} instances protected from scale in"

    instances.each { |instance| params[:instance_ids].push(instance.instance_id) }

    return if (protected_count == 0)

    begin
      _autoscaling_client.set_instance_protection(params)
      Log.debug "Removed Instance protection from ASG #{autoscaling_group_name.inspect}"
    rescue => e
      Log.warn "Failed to remove instance protection from ASG #{autoscaling_group_name.inspect}"
      raise "Failed to remove instance protection from ASG #{autoscaling_group_name.inspect} - #{e}"
    end
  end

  def autoscaling_set_capacity(
    autoscaling_group_name: nil,
    min_size: nil,
    desired_capacity: nil,
    max_size: nil
  )

    return if !min_size and !max_size and !desired_capacity

    params = {}
    params[:auto_scaling_group_name] = autoscaling_group_name
    params[:min_size] = min_size.to_i unless min_size.nil?
    params[:max_size] = max_size.to_i unless max_size.nil?
    params[:desired_capacity] = desired_capacity.to_i unless desired_capacity.nil?

    _autoscaling_client.update_auto_scaling_group(params)
  end

  def autoscaling_wait_for_capacity(
    autoscaling_group_name:,
    min_size: nil,
    max_size: nil,
    max_attempts: 60,
    delay: 30
  )

    if !min_size and !max_size
      Log.warn "Skipping wait for ASG to reach capacity - no min or max size was provided"
      return false
    end

    # Minimum of 1 attempt
    max_attempts = [1, max_attempts].max

    (1..max_attempts).each do |attempt|
      resp = _autoscaling_client.describe_auto_scaling_groups(
        auto_scaling_group_names: [autoscaling_group_name],
        max_records: 1,
      )

      # ASG doesn't exist
      if resp.auto_scaling_groups.nil? or resp.auto_scaling_groups.empty?
        raise "ASG #{autoscaling_group_name.inspect} does not exist"
      end

      # Count instances which are or were previously part of the ASG (don't count Pending or Standby instances)
      current_capacity = resp.auto_scaling_groups[0].instances.select { |instance| instance.lifecycle_state !~ /(Pending)|(Standby)|(Detach)/ }.size

      Log.debug "ASG #{autoscaling_group_name.inspect} current capacity is #{current_capacity}, target capacity is (min #{min_size || 'X'}, max #{max_size || 'X'})"

      # Return if capacity requirements have been met
      return true if (min_size.nil? or current_capacity >= min_size.to_i) && (max_size.nil? or current_capacity <= max_size.to_i)

      sleep(delay) if attempt != max_attempts
    end

    raise "Timed out waiting for ASG to reach target capacity"
  end

  def clean_up_networkinterfaces(
    component_name: nil,
    autoscaling_group_name: nil
  )
    begin
      secretmanagement_lambda_name = Context.component.variable(
        component_name,
        "SecretManagementLambdaName",
        nil
      )
      secretmanagementtermination_lambda_name = Context.component.variable(
        component_name,
        "SecretManagementTerminationLambdaName",
        nil
      )

      if secretmanagement_lambda_name.nil? && secretmanagementtermination_lambda_name.nil?
        Log.debug "Skipping cleanup - no network network interfaces found attached to autoscaling group #{autoscaling_group_name.inspect} lifecycle hook lambda."
      else
        requester_ids_array = []
        requester_ids_array.push("*:#{secretmanagement_lambda_name}") unless secretmanagement_lambda_name.nil?
        requester_ids_array.push("*:#{secretmanagementtermination_lambda_name}") unless secretmanagementtermination_lambda_name.nil?

        network_interfaces = AwsHelper.ec2_lambda_network_interfaces(
          requester_ids: requester_ids_array
        )

        if network_interfaces.nil? || network_interfaces.empty?
          Log.debug "Skipping cleanup - no network network interfaces found attached to #{autoscaling_group_name.inspect}"
        else
          Log.debug "Removing network interfaces attached to #{requester_ids_array}"
          AwsHelper.ec2_delete_network_interfaces(network_interfaces)
        end
      end
    rescue => e
      Log.warn "Failed to clean up network interfaces for #{component_name.inspect} and autoscaling group name #{autoscaling_group_name.inspect} during teardown - #{e}"
    end
  end

  def _autoscaling_client
    # Create a new client if it doesn't exist yet
    @client_mutex.synchronize do
      if @autoscaling_client.nil?

        # Creat the CloudFormation client
        Log.debug "Creating a new AWS Autoscaling client"

        # Build the client parameters
        params = {}
        params[:http_proxy] = @proxy unless @proxy.nil?
        params[:region] = @region unless @region.nil?
        params[:retry_limit] = @retry_limit unless @retry_limit.nil?
        credentials = _provisioning_credentials || _control_credentials || nil
        params[:credentials] = credentials unless credentials.nil?

        @autoscaling_client = Aws::AutoScaling::Client.new(params)
      end
    end

    return @autoscaling_client
  end
end
