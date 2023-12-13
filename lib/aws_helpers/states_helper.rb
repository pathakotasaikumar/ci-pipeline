# Module provides helper methods for AWS::States::Client
module StatesHelper
  def _states_helper_init
    @states_client = nil
  end

  # Stars execution of a step function state machine
  # @param state_machine_arn [String] State machine arn targeted for execution
  # @param name [String] Name for execution
  # @param input [String] Json formatting string input
  # @return [String] Execution ARN id
  def states_start_execution(
    state_machine_arn:,
    name: nil,
    input: nil
  )
    params = {
      state_machine_arn: state_machine_arn,
      input: input
    }

    params[:name] = name unless name.nil?

    Log.debug "Executing state machine: #{state_machine_arn}, name: #{name}, params: #{params.inspect}"
    _states_client.start_execution(params).execution_arn
  rescue => e
    raise "Unable to start execution for state machine #{state_machine_arn} - #{e}"
  end

  # Retrieves results of a state machine execution
  # @param execution_arn [String] ARN of a state machine execution
  # @return [Hash] Json output of a state machine execution
  def states_execution_result(execution_arn)
    _states_client.describe_execution(execution_arn: execution_arn).output
  rescue => e
    raise e
  end

  # Waits until execution is complete
  # @param execution_arn [String] ARN id of a state machine execution
  # @max_attempts [Integer] number of attempts
  # @delay [Integer] number of secodns to wait between each execution
  def states_wait_until_complete(execution_arn:, max_attempts: 60, delay: 30)
    Log.debug "Waiting for execution completion of workflow: #{execution_arn}"
    status = "RUNNING"
    count = 0

    loop do
      raise "Maximum attempts #{max_attempts} has been reached while waiting for execution to complete" if count >= max_attempts

      status = _states_client.describe_execution(
        execution_arn: execution_arn
      ).status
      count += 1
      sleep delay
      Log.debug "Waiting for workflow completion - #{count}"
      break unless status == 'RUNNING'
    end

    if status != 'SUCCEEDED'
      raise "Execution #{execution_arn} has completed with status: #{status}"
    end

    Log.debug "Execution #{execution_arn} has completed with status: #{status}"
  rescue => e
    raise e
  end

  # Returns an instance of AWS::States::Client
  # @return [Object] AWS::States::Client
  def _states_client
    # Create a new client if it doesn't exist yet
    @client_mutex.synchronize do
      if @states_client.nil?
        # Build the client parameters
        params = {}
        params[:http_proxy] = @proxy unless @proxy.nil?
        params[:region] = @region unless @region.nil?
        params[:retry_limit] = @retry_limit unless @retry_limit.nil?
        credentials = _provisioning_credentials || _control_credentials || nil
        params[:credentials] = credentials unless credentials.nil?

        @states_client = Aws::States::Client.new(params)
      end
    end

    return @states_client
  end
end
