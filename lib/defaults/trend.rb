require_relative "environment"

module Defaults
  module Trend
    extend self

    def trend_dsm_url
      Context.environment.variable('trend_dsm_url', nil)
    end

    def trend_dsm_tenant_id
      Context.environment.variable('trend_dsm_tenant_id', nil)
    end

    def trend_dsm_token
      Context.environment.variable('trend_dsm_token', nil)
    end

    def trend_dsm_saas_proxy
      Context.environment.variable('trend_dsm_saas_proxy', nil)
    end

    def trend_agent_activation_url
      Context.environment.variable('trend_agent_activation_url', nil)
    end

    # returns Atora Lambda function arn set in SSM parameter
    def atora_release_arn
      Context.environment.variable('atora_release_arn', nil)
    end

    # @return [String] Whether we should use the account specific invocation role
    def atora_invocation_role
      Context.environment.variable('atora_invocation_role', nil)
    end
  end
end
