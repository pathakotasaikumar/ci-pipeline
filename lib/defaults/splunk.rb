module Defaults
  module Splunk
    extend self

    def splunk_url
      Context.environment.variable('splunk_url', nil)
    end

    def splunk_token_password
      Context.environment.variable('splunk_token_password', nil)
    end
  end
end
