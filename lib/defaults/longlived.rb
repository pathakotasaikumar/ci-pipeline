module Defaults
  module Longlived
    extend self

    # @return [String] Value for Longlived production puppetmaster server
    def puppet_server
      Context.environment.variable('lri_puppet_server', nil)
    end

    # @return [String] Value for Longlived non-production default puppet environment
    def puppet_qcp_lri_nonproduction
      Context.environment.variable('lri_puppet_qcp_lri_nonproduction', 'qcp_lri_nonproduction')
    end

    # @return [String] Value for Longlived production default puppet environment
    def puppet_qcp_lri_production
      Context.environment.variable('lri_puppet_qcp_lri_production', 'qcp_lri_production')
    end

    # @return [String] Value for Longlived puppet environment based on service tier
    def windows_patchgroup
      Context.environment.variable('windows_patchgroup', 'windows-core-baseline')
    end

    # @return [String] Value for Longlived puppet environment based on service tier
    def rhel_patchgroup
      Context.environment.variable('rhel_patchgroup', 'rhel-core-baseline')
    end

    # @return [String] Value for Longlived puppet environment based on service tier
    def centos_patchgroup
      Context.environment.variable('centos_patchgroup', 'centos-core-baseline')
    end
  end
end
