#
# API Gateway Prameters
#

module Defaults
  module ApiGateway
    extend self

    # Returns Qantas API Gateway admin username
    # @return [String] Api gateway admin registration username
    def api_gateway_username
      Context.environment.variable('api_gateway_username', nil)
    end

    # Returns Qantas API Gateway admin user password
    # @return [String] Api gateway admin registration password
    def api_gateway_password
      Context.environment.variable('api_gateway_password', nil)
    end

    # Returns Qantas API gateway registration endpoint based on environment
    # @return [String] Api Gateway admin portal registration endpoint
    def api_gateway_admin_url
      sections = Defaults.sections
      if sections[:env] == 'prod'
        Context.environment.variable('api_gateway_admin_url_prod', nil)
      else
        Context.environment.variable('api_gateway_admin_url_nonp', nil)
      end
    end

    # Returns Qantas API gateway cross account role ARN based on environment
    # @return [String] Api Gateway admin cross account role arn
    def api_gateway_cross_account_role_arn
      sections = Defaults.sections
      if sections[:env] == 'prod'
        Context.environment.variable('api_gateway_cross_account_role_arn_prod', nil)
      else
        Context.environment.variable('api_gateway_cross_account_role_arn_nonp', nil)
      end
    end

    # Returns Qantas API gateway derived registration key
    # @return [String] Api Gateway admin portal registration endpoint
    def api_gateway_registration_key
      key = Context.environment.variable('api_gateway_custom_key', nil)
      return key unless key.nil?

      sections = Defaults.sections
      "#{sections[:plan_key]}_#{sections[:branch].gsub(/[^\w]/, '-')}".upcase
    end
  end
end
