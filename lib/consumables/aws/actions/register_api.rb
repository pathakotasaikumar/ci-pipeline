require 'consumables/aws/actions/http_request'
require 'pipeline/helpers/http'

# Extends generic HTTPRequest action
# Executes REST API call for registration of an endpoint with API Gateway
class RegisterApi < HTTPRequest
  include Pipeline::Helpers::HTTP

  def initialize(component: nil, params: nil, stage: nil, step: nil)
    @url = Defaults.api_gateway_admin_url

    super

    raise ArgumentError, "Basepath parameter must be specified" if params['Basepath'].nil?
    raise ArgumentError, "swagger parameter must be specified" if params['Swagger'].nil? || params['Swagger'].empty?
    raise ArgumentError, "apiConf parameter must be specified" if params['ApiConf'].nil? || params['ApiConf'].empty?

    # Add Api registration specific parameters
    @type = 'POST'
    @ssl = true
    @headers = {
      'apigateway-apikey' => Defaults.api_gateway_registration_key,
      'apigateway-basepath' => params['Basepath'],
      'content-type' => 'application/json'
    }

    @payload = {
      'swagger' => params['Swagger'],
      'apiConf' => params['ApiConf']
    }
    @target = params.fetch('Target', '@released')
    @stop_on_error = params.fetch('StopOnError', true).to_s
    # Override username and password instance variables in super class
    @username = Defaults.api_gateway_username
    @password = Defaults.api_gateway_password
  end

  # @see Action#valid_stages
  def valid_stages
    [:all]
  end

  # @see Action#valid_components
  def valid_components
    [:all]
  end

  # @see Action#Invoke
  def invoke
    super

    if @component.type.downcase == 'aws/lambda'
      component_name = @component.component_name

      target_arn = if @target == '@released'
                     Context.component.variable(component_name, 'ReleaseArn')
                   else
                     Context.component.variable(component_name, 'DeployArn')
                   end

      statement_id = 'LambdaInvokePermission'

      raise "Unable to obtain ARN for #{component_name} based on target #{@target}" if target_arn.nil?

      resp = AwsHelper.lambda_get_policy(function_name: target_arn)

      unless resp.empty?
        is_statement_exist = _validate_lambda_policy_statement(
          policy_statement: JSON.parse(resp.policy),
          sid_to_validate: statement_id
        )
        if is_statement_exist
          Log.debug 'The lambda invoke permission is exist, so skipping add_permission action.'
          return
        end
      end

      begin
        # Add lambda permission
        AwsHelper.lambda_add_permission(
          function_name: target_arn,
          principal: Defaults.api_gateway_cross_account_role_arn,
          action: 'lambda:InvokeFunction',
          statement_id: statement_id
        )
        Log.info "Successfully added invoke permission on #{component_name} and target #{target_arn}"
      rescue => e
        msg = "Failed to add invoke permission to the function #{@target} -#{e}"
        if @stop_on_error == 'true'
          raise "#{msg}. Failing SetRegisterApi action"
        else
          Log.warn "#{msg}. Skipping SetRegisterApi action"
          return
        end
      end
    end
  end

  private

  # function to inspect the lambda policy
  # @param policy_statement [Hash] stack id
  # @param sid_to_validate [String] statement value to validate
  # @return  [Boolean]
  def _validate_lambda_policy_statement(policy_statement:, sid_to_validate:)
    statement_array = policy_statement['Statement']
    statement_array.each do |statement|
      return true if statement['Sid'] == sid_to_validate
    end
    return false
  end
end
