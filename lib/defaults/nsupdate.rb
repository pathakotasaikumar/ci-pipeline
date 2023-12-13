# frozen_string_literal: true

module Defaults
  module Nsupdate
    module_function

    # @return [String] Value for AD DC list
    def ad_domain_dc_list
      ad_dcs_default = %w[
        awssyddc07
        awssyddc08
        awssyddc09
        awssyddc10
        awssyddc11
        awssyddc12
      ]
      Context.environment.variable('ad_domain_list', ad_dcs_default)
    end

    # @return [String] Value for key tab path
    def keytab_path
      Context.environment.variable(
        'kerberos_keytab_path',
        '/data/bambooagent/dns-qcpaws.keytab'
      )
    end

    # @return [String] Value for ad principle
    def ad_principle
      Context.environment.variable(
        'kerberos_principle',
        'SVC_Atlassian'
      )
    end

    # @return [String] Value for ad zone dns
    def ad_zone_dns
      'qcpaws.qantas.com.au'
    end
  end
end
