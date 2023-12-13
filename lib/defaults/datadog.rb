module Defaults
  module Datadog
    extend self

    # @return [String] Value for Qualys activation id
    def datadog_api_keys
      Context.environment.variable('datadog_api_keys', nil)
    end
  end
end
