#
# Bamboo CI to CD integration parameters
#

module Defaults
  module Bamboo
    extend self

    # @return [String] Value for user account for Bamboo CD
    def bamboo_pipeline_user
      Context.environment.variable('pipeline_user', nil)
    end

    # @return [String] Value for password for Bamboo CD
    def bamboo_pipeline_password
      Context.environment.variable('pipeline_password', nil)
    end

    # @return [String] String value for URL for Bamboo CD
    def bamboo_cd_api_baseurl
      Context.environment.variable('baseurl_bamboo_cd_api', nil)
    end

    # @return [String] String value for enable cd integration flag
    def invoke_bamboocd_enable
      Context.environment.variable('invoke_bamboocd_enable', nil)
    end

    # @return [String] String value for URL for Bamboo CD ASE to be invoked
    def invoke_bamboocd_ase
      Context.environment.variable('invoke_bamboocd_ase', 'DEV')
    end

    def invoke_bamboocd_stage
      Context.environment.variable('invoke_bamboocd_stage', 'Deploy')
    end
  end
end
