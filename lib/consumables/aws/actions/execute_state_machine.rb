# Class implements action responsible for invoking AWS::StepFunctions::StateMachine
# Input parameter can be specified as payload into the state machine
# By default the action will wait for up to 60 minutes until execution is complete

require "action"
class ExecuteStateMachine < Action
  def initialize(component: nil, params: nil, stage: nil, step: nil)
    super

    @state_machine_name ||= params.fetch('StateMachineName', nil)
    @target ||= params.fetch('Target', '@deployed')
    @input ||= params.fetch('Input', nil)

    @stop_on_error = params.fetch('StopOnError', 'true')
    @wait_for_completion = params.fetch('WaitForCompletion', 'true')
    @timeout = params.fetch('Timeout', 3600)

    if @state_machine_name.nil? || @state_machine_name.empty?
      raise ArgumentError, "Parameter/StateMachine must be specified"
    end
  end

  # @see Action#valid_stages
  def valid_stages
    %w(
      PostDeploy
      PreRelease
      PostRelease
      PreTeardown
    )
  end

  # @see Actions#valid_components
  def valid_components
    %w(
      aws/state-machine
    )
  end

  # Invokes execution of the target state machine
  def invoke
    params = { state_machine_arn: _state_machine_arn(@state_machine_name) }

    unless @input.nil? || @input.empty?
      params[:input] = Context.component.replace_variables(@input).to_json
    end

    execution_arn = AwsHelper.states_start_execution(params)

    return if @wait_for_completion.to_s != 'true'

    Log.debug "Waiting for execution completion of workflow: "\
      "#{execution_arn} - Timeout: #{@timeout.to_i} seconds"

    AwsHelper.states_wait_until_complete(
      execution_arn: execution_arn,
      max_attempts: (@timeout.to_i / 30.0).ceil,
      delay: 30
    )

    Log.output "Successfully executed '#{@component.component_name}' action - #{self.class}"
    Log.output YAML.dump(JSON.parse(AwsHelper.states_execution_result(execution_arn)))
  rescue => e
    Log.error "Failed to execute '#{@component.component_name}' action #{self.class} - #{e}"
    if @stop_on_error == 'true'
      raise "Failed to execute '#{@component.component_name}' action #{self.class} - #{e}"
    end
  end

  private

  # Returns arn for the state machine
  def _state_machine_arn(state_machine_name)
    Context.component.variable(@component.component_name, "#{state_machine_name}Arn")
  end
end
