#
# SNOW parameters
#

module Defaults
  module Snow
    extend self

    # Use cases
    # prod && skip_alm == nil (default) -> enabled
    # prod && skip_alm == true -> disabled
    # prod && skip_alm == false -> enabled
    # nonp && skip_alm == nil -> disabled
    # nonp && skip_alm == true -> disable
    # nonp && skip_alm == false -> enabled
    # @return [Boolean] ALM enabled flag
    def snow_enabled
      skip_for_environment = Defaults.sections[:env] == "prod" ? 'false' : 'true'
      enabled = Context.environment.variable('skip_alm', skip_for_environment) == 'false'

      return enabled
    end

    # @return [String] Value for ServiceNow api endpoint
    def snow_endpoint
      Context.environment.variable('snow_endpoint', nil)
    end

    # @return [String] Value for ServiceNow username for API access
    def snow_user
      Context.environment.variable('snow_user', nil)
    end

    # @return [String] String value for ServiceNow password for API access
    def snow_password
      Context.environment.variable('snow_password', nil)
    end
  end
end
