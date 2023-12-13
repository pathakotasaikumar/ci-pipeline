module Defaults
  module Qualys
    extend self

    # @return [String] Value for Qualys activation id
    def qualys_activation_id
      Context.environment.variable('qualys_activation_id', nil)
    end

    # returns AQOS Lambda function arn set in SSM parameter
    def aqos_release_dns
      Context.environment.variable('aqos_release_dns', nil)
    end

    # returns AQOS Lambda function arn set in SSM parameter
    def aqos_release_arn
      Context.environment.variable('aqos_release_arn', nil)
    end
  end
end
