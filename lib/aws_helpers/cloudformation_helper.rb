require 'aws-sdk'
require 'securerandom'

require "#{BASE_DIR}/lib/service_container"
require "#{BASE_DIR}/lib/services/retryable_service.rb"

include Qantas::Pipeline

module CloudFormationHelper
  # retry_service method will come from AwsHelperClass

  def _cloudformation_helper_init
    @cloudformation_client = nil
  end

  def _cloudformation_retry_options
    # allow retry for exceptions which have the following values
    # the aim is to cover cases where AWS throttles calls

    {
      :allowed_exception_messages => [
        /Rate exceeded/,
        /too many/,
        /Timeout/,
        /timeout/
      ]
    }
  end

  # Retrieve a CloudFormation client
  def _cloudformation_client
    # Create a new client if it doesn't exist yet
    @client_mutex.synchronize do
      if @cloudformation_client.nil?

        # Creat the CloudFormation client
        Log.debug "Creating a new AWS CloudFormation client"

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

        @cloudformation_client = Aws::CloudFormation::Client.new(params)
      end
    end

    return @cloudformation_client
  end

  def _cfn_get_and_log_stack_events(stack_id, stack_events)
    begin
      # Get any stack events we may have missed
      new_events = _cfn_get_stack_events(stack_id, stack_events.last ? stack_events.last.event_id : nil)
      _log_stack_events(new_events)
      stack_events.concat(new_events)
    rescue => e
      Log.warn "#{e}"
    end
  end

  def _trace_safe_call_start(api_name)
    Log.debug "Calling AWS API: #{api_name}"
  end

  def _trace_safe_call_finish(api_name, result)
    Log.debug "Finished calling AWS API: #{api_name}"
    Log.debug " - success on retry: #{result[:result_try]}"
    Log.debug " - full retry history: #{result[:attempts].to_yaml}"
  end

  def _safe_get_template(params)
    api_name = "Aws::CloudFormation::Client.get_template"
    _trace_safe_call_start(api_name)

    result = retry_service.exec_with_retry(options: _cloudformation_retry_options) {
      call_result = _cloudformation_client.get_template(params)
      next call_result
    }

    _trace_safe_call_finish(api_name, result)

    result[:result_value]
  end

  def _safe_describe_stacks(params)
    api_name = "Aws::CloudFormation::Client.describe_stacks"
    _trace_safe_call_start(api_name)

    result = retry_service.exec_with_retry(options: _cloudformation_retry_options) {
      call_result = _cloudformation_client.describe_stacks(params)
      next call_result
    }

    _trace_safe_call_finish(api_name, result)

    result[:result_value]
  end

  def _cfn_get_stack_status(stack_name:)
    stacks = _safe_describe_stacks({ stack_name: stack_name }).stacks
    return stacks.first.stack_status unless stacks.size != 1
  rescue Aws::CloudFormation::Errors::ValidationError => e
    raise "Failed to retrieve stack status for stack: #{stack_name}) - #{e}" unless e.message.end_with? "does not exist"
  rescue => e
    raise "Failed to retrieve stack status for stack: #{stack_name}) - #{e}"
  end

  def _cfn_get_stack_events(stack_id, latest_event_id = nil)
    new_events = []
    event_params = {
      stack_name: stack_id
    }
    begin
      response = _cloudformation_client.describe_stack_events(event_params)
      response.stack_events.each do |event|
        break if event.event_id == latest_event_id

        new_events << event
      end
    rescue => e
      raise "Failed to retrieve stack events (StackId = stack_id.inspect) - #{e}"
    end

    return new_events.reverse
  end

  def _stack_event_error?(stack_event)
    result = false

    error_events = [
      'CREATE_FAILED'
    ]

    if !stack_event.nil? && stack_event.respond_to?(:resource_status) && !stack_event.resource_status.nil?
      result = error_events.include?(stack_event.resource_status.upcase)
    end

    result
  end

  def _log_stack_events(events)
    events.each do |event|
      log_message = [
        "CloudFormation event:",
        event.timestamp,
        event.stack_name,
        event.resource_type,
        event.logical_resource_id.inspect,
        event.resource_status,
        event.resource_status_reason
      ].join " - "

      if _stack_event_error?(event)
        Log.error(log_message)
      else
        Log.debug(log_message)
      end
    end
  end

  # @param [String] stack_name
  # @param [Hash] template
  # @param [Object] tags
  # @param [Numeric] wait_delay
  # @param [Numeric] max_attempts
  # @param template_parameters [Hash] Associated list of parameter keys and values
  def cfn_create_stack(
    stack_name: nil,
    template: nil,
    tags: nil,
    wait_delay: 30,
    max_attempts: 240,
    template_parameters: nil
  )

    raise ArgumentError, "Parameter 'stack_name' is mandatory" if stack_name.nil? or stack_name.empty?
    raise ArgumentError, "Parameter 'template' is mandatory" if template.nil? or !template.is_a? Hash
    raise ArgumentError, "Parameter 'tags' is mandatory" if tags.nil? or !tags.is_a? Array

    outputs = {}

    begin
      params = {
        stack_name: stack_name,
        template_body: JSON.generate(template),
        tags: tags,
        capabilities: ["CAPABILITY_IAM"],
        on_failure: "DO_NOTHING",
      }

      if !template_parameters.nil? && !template_parameters.empty?
        params[:parameters] = cfn_parameter_list template_parameters
      end

      Log.debug "Creating a new CloudFormation stack with stack_name #{stack_name.inspect}"
      response = _cloudformation_client.create_stack(params)

      outputs = {
        "StackName" => stack_name,
        "StackId" => response.stack_id,
      }
    rescue => e
      Log.snow "ERROR: Creation of CloudFormation stack #{stack_name.inspect} has failed"
      raise RuntimeError, "Creation of CloudFormation stack #{stack_name.inspect} has failed - #{e}"
    end

    # Wait for stack creation to complete/fail/timeout
    Log.debug "Waiting for CloudFormation stack #{response.stack_id} to complete"
    sleep 5
    stack_events = []
    begin
      _cloudformation_client.wait_until(:stack_create_complete, { stack_name: response.stack_id }) do |waiter|
        waiter.delay = wait_delay
        waiter.max_attempts = max_attempts

        waiter.before_attempt do
          # Before each status call by the waiter, get the stack events
          _cfn_get_and_log_stack_events(response.stack_id, stack_events)
          sleep rand(1..3)
        end
      end
    rescue Aws::Waiters::Errors::TooManyAttemptsError => e
      Log.snow "ERROR: CloudFormation stack creation timed out (StackId = #{response.stack_id.inspect})"
      raise ActionError.new(outputs), "CloudFormation stack creation timed out (StackId = #{response.stack_id.inspect}) - #{e}"
    rescue Aws::Waiters::Errors::WaiterFailed => e
      Log.snow "ERROR: CloudFormation stack creation failed (StackId = #{response.stack_id.inspect})"
      raise ActionError.new(outputs), "CloudFormation stack creation failed (StackId = #{response.stack_id.inspect}) - #{e}"
    ensure
      # Get any stack events we may have missed
      sleep rand(1..3)
      _cfn_get_and_log_stack_events(response.stack_id, stack_events)
    end

    # Retrieve and save the stack's outputs
    Log.debug "Created CloudFormation stack #{response.stack_id.inspect}"
    Log.snow "Created CloudFormation stack #{response.stack_id.inspect}"

    begin
      outputs = outputs.merge(cfn_get_stack_outputs(response.stack_id))
    rescue => e
      raise ActionError.new(outputs), "Failed to retrieve stack outputs after creation (StackId = #{response.stack_id.inspect}) - #{e}"
    end

    return outputs
  end

  # @param parameters [Hash] Associated list of parameter keys and values
  # @return [Array] Converted list of parameters for cfn client consumption
  def cfn_parameter_list(parameters)
    raise 'Parameters argument must be a Hash' unless parameters.is_a? Hash

    Log.debug "Stack uses [#{parameters.count}] parameters"
    parameter_list = []
    parameters.each do |key, value|
      parameter_list << {
        parameter_key: key,
        parameter_value: value
      }
      Log.debug " - Name:[#{key}]"
    end
    parameter_list
  end

  def cfn_update_stack(
    stack_name:,
    template: nil,
    wait_delay: 30,
    max_attempts: 240,
    use_previous_template: false,
    parameters: nil
  )

    unless use_previous_template
      raise ArgumentError, "Parameter 'template' is mandatory" if template.nil? or !template.is_a? Hash
    end

    begin
      # Create a stack change set
      Log.info "Creating stack update change set"

      params = {
        stack_name: stack_name,
        capabilities: ["CAPABILITY_IAM"],
        change_set_name: "cs-#{SecureRandom.uuid}",
        use_previous_template: use_previous_template
      }
      params[:template_body] = JSON.generate(template) unless template.nil?
      params[:parameters] = parameters unless parameters.nil?

      change_set_id = (_cloudformation_client.create_change_set(params)).id

      # Determine if there are any changes to apply
      response = _cloudformation_client.describe_change_set(change_set_name: change_set_id)
      attempts = 0
      while response.status == "CREATE_PENDING" or response.status == "CREATE_IN_PROGRESS"
        if attempts > 60
          _cloudformation_client.delete_change_set(change_set_name: change_set_id)
          raise "Change set creation has timed out"
        end
        sleep(10)
        attempts += 1
        response = _cloudformation_client.describe_change_set(change_set_name: change_set_id)
      end

      if response.changes.empty?
        Log.info "No changes required for stack #{stack_name.inspect}"
        _cloudformation_client.delete_change_set(change_set_name: change_set_id)
        return cfn_get_stack_outputs(stack_name)
      else
        response.changes.each do |change|
          rc = change.resource_change
          Log.debug [
            "Stack update:",
            response.stack_name,
            rc.action,
            rc.resource_type,
            rc.logical_resource_id.inspect,
            rc.scope.inspect
          ].join " - "
        end
      end

      # Apply the changes
      Log.info "Executing stack update changes for stack: #{stack_name}"
      stack_events = _cfn_get_stack_events(stack_name, nil)
      _cloudformation_client.execute_change_set(change_set_name: change_set_id)
    rescue => e
      Log.snow "ERROR: Update of CloudFormation stack has failed (StackName = #{stack_name.inspect})"
      raise RuntimeError, "Update of CloudFormation stack has failed (StackName = #{stack_name.inspect}) - #{e}"
    end

    # Wait for stack update to complete/fail/timeout
    Log.debug "Waiting for update of CloudFormation stack #{stack_name} to complete"
    sleep 5
    begin
      _cloudformation_client.wait_until(:stack_update_complete, { stack_name: stack_name }) do |waiter|
        waiter.delay = wait_delay
        waiter.max_attempts = max_attempts
        waiter.before_attempt do
          # Before each status call by the waiter, get the stack events
          _cfn_get_and_log_stack_events(stack_name, stack_events)
          sleep rand(1..5)
        end
      end
    rescue Aws::Waiters::Errors::TooManyAttemptsError => e
      Log.snow "ERROR: CloudFormation stack update timed out (StackName = #{stack_name.inspect})"
      raise ActionError.new(), "CloudFormation stack update timed out (StackName = #{stack_name.inspect}) - #{e}"
    rescue Aws::Waiters::Errors::WaiterFailed => e
      Log.snow "ERROR: CloudFormation stack update failed (StackName = #{stack_name.inspect})"
      raise ActionError.new(), "CloudFormation stack update failed (StackName = #{stack_name.inspect}) - #{e}"
    ensure
      # Get any stack events we may have missed
      sleep rand(1..3)
      _cfn_get_and_log_stack_events(stack_name, stack_events)
    end

    # Retrieve and save the stack's outputs
    Log.snow "CloudFormation stack has been successfully updated (StackName = #{stack_name.inspect})"
    Log.debug "CloudFormation stack has been successfully updated (StackName = #{stack_name.inspect})"

    return cfn_get_stack_outputs(stack_name)
  end

  def cfn_stack_exists(stack_name)
    # Retrieve and save the stack's outputs
    Log.debug "Checking for CloudFormation Stack: #{stack_name}"
    stack_id = nil
    begin
      response = _safe_describe_stacks({ stack_name: stack_name })
      stack_id = response.stacks[0].stack_id
    rescue Aws::CloudFormation::Errors::ValidationError => e
      raise unless e.message.end_with? "does not exist"

      stack_id = nil
    rescue => e
      raise ActionError.new(), "An error occurred while checking if stack exists - #{e}"
    end

    return stack_id
  end

  def cfn_get_stack_outputs(stack_name)
    # Retrieve and save the stack's outputs
    Log.debug "Retrieving stack outputs for: #{stack_name}"
    begin
      response = _safe_describe_stacks({ stack_name: stack_name })
      raise "No stacks returned with name #{stack_name}" if response.stacks.empty?
    rescue => e
      raise ActionError.new(), "An error occurred while retrieving stack outputs - #{e}"
    end

    outputs = {}
    outputs['StackName'] = response.stacks[0].stack_name
    outputs['StackId'] = response.stacks[0].stack_id

    response.stacks[0].outputs.each do |stack_output|
      outputs[stack_output.output_key] = stack_output.output_value
    end

    return outputs
  end

  def _raise_QCP_2486(stack_name)
    raise_stack_name = "ams03-p106-01-dev-QCP-2486-vol-persist-ActiveBuilds"

    if stack_name == raise_stack_name
      Log.warn "failing on active builds stack: #{raise_stack_name}"
      raise "failing on active builds stack: #{raise_stack_name}"
    end
  end

  def cfn_get_template(stack_name)
    # TODO, this is only for testing QCP-2486
    # _raise_QCP_2486(stack_name)

    # Retrieve and save the stack's outputs
    Log.debug "Retrieving stack template for: #{stack_name}"
    begin
      response = _safe_get_template({ stack_name: stack_name })
    rescue => e
      raise "An error occurred while retrieving the stack template - #{e}"
    end

    return JSON.load(response.template_body)
  end

  def cfn_wait_until_stack_deletable(
    stack_name: nil,
    wait_delay: 15,
    max_attempts: 240
  )

    undeletable_statuses = [
      "ROLLBACK_IN_PROGRESS",
      "UPDATE_COMPLETE_CLEANUP_IN_PROGRESS",
      "UPDATE_ROLLBACK_COMPLETE_CLEANUP_IN_PROGRESS",
      "UPDATE_ROLLBACK_IN_PROGRESS"
    ]

    params = {
      stack_name: stack_name,
    }

    begin
      response = _safe_describe_stacks(params)
      raise "Expecting 1 matching stack, but found #{response.stacks.length}" unless response.stacks.length == 1

      attempt = 0
      while undeletable_statuses.include? response.stacks[0].stack_status
        attempt += 1
        raise "Exceeded maximum number of attempts" if attempt > max_attempts

        # Sleep before we check again
        sleep wait_delay

        # Check the status of the stack
        response = _safe_describe_stacks(params)
        raise "Expecting 1 matching stack, but found #{response.stacks.length}" unless response.stacks.length == 1
      end
    rescue Aws::CloudFormation::Errors::ValidationError => e
      if e.message.end_with? "does not exist" and Context.environment.variable('cfn_skip_delete_on_missing', false)
        Log.debug("Ignore waiting for stack deletion due non-existing stack - #{e}")
        return
      else
        raise "Failed cloudformation validation - #{e}"
      end
    rescue => e
      raise "Failed while waiting for stack to become deletable - #{e}"
    end
  end

  def cfn_delete_stack(stack_name, wait_for_completion = true, retain_resources = [])
    raise ArgumentError, "Parameter 'stack_name' is mandatory" if stack_name.nil? or stack_name.empty?

    # Wait for the stack to be deletable
    cfn_wait_until_stack_deletable(stack_name: stack_name)

    # Delete the stack
    begin
      Log.debug "Deleting CloudFormation stack with name/id #{stack_name.inspect}"
      stack_events = _cfn_get_stack_events(stack_name, nil)
      params = { stack_name: stack_name }
      params[:retain_resources] = retain_resources unless retain_resources.nil? or retain_resources.empty?
      _cloudformation_client.delete_stack(params)
    rescue => e
      if e.message.end_with? "does not exist" and Context.environment.variable('cfn_skip_delete_on_missing', false)
        Log.debug("Ignoring stack deletion due non-existing stack - #{e}")
        return
      else
        Log.snow "ERROR: Failed to delete CloudFormation stack (StackId = #{stack_name.inspect})"
        raise RuntimeError, "Failed to delete CloudFormation stack (StackId = #{stack_name.inspect}) - #{e}"
      end
    end

    if wait_for_completion
      Log.debug "Waiting for CloudFormation stack #{stack_name.inspect} to delete"
      begin
        sleep 5
        _cloudformation_client.wait_until(:stack_delete_complete, { stack_name: stack_name }) do |waiter|
          waiter.before_attempt do
            # Before each status call by the waiter, get the stack events
            _cfn_get_and_log_stack_events(stack_name, stack_events)
            sleep rand(1..5)
          end
        end
      rescue Aws::Waiters::Errors::TooManyAttemptsError => e
        Log.snow "ERROR: CloudFormation stack delete timed out (StackId = #{stack_name.inspect})"
        raise ActionError.new(), "CloudFormation stack delete timed out (StackId = #{stack_name.inspect}) - #{e}"
      rescue Aws::Waiters::Errors::WaiterFailed => e
        Log.snow "ERROR: CloudFormation stack delete failed (StackId = #{stack_name.inspect})"
        raise ActionError.new(), "CloudFormation stack delete failed (StackId = #{stack_name.inspect}) - #{e}"
      end
    end

    Log.debug "CloudFormation stack has been successfully deleted (StackId = #{stack_name.inspect})"
    Log.snow "CloudFormation stack has been successfully deleted (StackId = #{stack_name.inspect})"
  end

  def cfn_describe_all_stacks
    stacks = []
    next_token = nil

    loop do
      response = _safe_describe_stacks({
        next_token: next_token
      })
      stacks += response.stacks
      next_token = response.next_token
      if next_token.nil?
        break
      end
    end

    return stacks
  end

  def get_stack_list(prefix, accepted_status)
    #Extract the existing stacks using the prefix pattern <amsid>-<entrpriseid>-<asid>-<env>-<branch>
    stack_name_list = []
    list_stacks = []
    next_token = nil
    loop do
      response_list_stacks = _cloudformation_client.list_stacks({
        next_token: next_token,
        stack_status_filter: accepted_status
      })
      list_stacks += response_list_stacks.stack_summaries.select{ |summary| summary[:stack_name] =~ /#{prefix}/ }
      next_token = response_list_stacks.next_token
      if next_token.nil?
        break
      end
    end
    stack_summary_list = list_stacks.select{ |summary| summary[:stack_name] =~ /#{prefix}/ }
    stack_summary_list.each do |stack_summary|
      stack_name_list.push(stack_summary[:stack_name])
    end

    return stack_name_list
  end

  def get_stack_comp_name(prefix, stack_name)
    #Get tag
    stackname_tags = _safe_describe_stacks({ stack_name: stack_name }).stacks[0].tags
    Log.info "Stack name tag found : #{stackname_tags}"

    if stack_name.include? "splunking"
      stack_tag_name = stack_name
    else
      stack_tag_name = stackname_tags.select{ |a| a[:key] == 'Name' }[0][:value]
    end

    #  Extracting comp name
    stack_tag_name_delim = stack_tag_name.split('-')
    prefix.split('-').each do |element|
        stack_tag_name_delim.delete(element)
    end

    if stack_name.include? "splunking"
      stack_tag_name_delim.delete("splunking")
    end

    return stack_tag_name_delim.join('-')
  end
end
