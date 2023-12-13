# Class implements action responsible for invoking AWS::Lambda::Function
# Input parameter can be specified as payload into the state machine
# Users may specify target parameter as @deployed or @released

require 'action'
require 'base64'
class InvokeLambda < Action
  def initialize(component: nil, params: nil, stage: nil, step: nil)
    super
    @fail_on_exception ||= params.fetch('FailOnException', false)
    @target ||= params.fetch('Target', '@deployed')
    @payload ||= params.fetch('Payload', nil)
    @stop_on_error = params.fetch('StopOnError', 'true')
  end

  def valid_stages
    %w(
      PostDeploy
      PreRelease
      PostRelease
      PreTeardown
    )
  end

  def valid_components
    %w(aws/lambda)
  end

  # Invokes target Lambda function
  def invoke
    target_arn = if @target == '@released'
                   Context.component.variable(@component.component_name, 'ReleaseArn', nil)
                 else
                   Context.component.variable(@component.component_name, 'DeployArn', nil)
                 end

    raise "Unable to obtain ARN for #{@component.component_name} based on target #{@target}" if target_arn.nil?

    params = {
      function_name: target_arn,
      log_type: 'Tail'
    }
    params[:payload] = Context.component.replace_variables(@payload).to_json unless @payload.nil? || @payload.empty?

    response = AwsHelper.lambda_invoke(**params)
    Log.output Base64.decode64(response.log_result) unless response.log_result.nil? || response.log_result.empty?

    # If fail_on_exception parameter is set to true, check for the function_error value in the response to raise exception on lambda function failure
    if @fail_on_exception == "true"
      if !response.function_error.nil?
        raise "Failed lambda function execution"
      end
    end

    Log.output "Successfully executed '#{@component.component_name}' action - #{self.class}"
  rescue => e
    Log.error "Failed to execute '#{@component.component_name}' action #{self.class} - #{e}"
    raise "Failed to execute '#{@component.component_name}' action #{self.class} - #{e}" if @stop_on_error == 'true'
  end
end
