#
# Wildcard Certificate Prameters
#

module Defaults
  module WildCardCertificate
    extend self

    # Returns NonProduction wildcard certificate name
    # @return [String] wildcard certificate name
    def nonp_wildcard_qcpaws_certificate_name
      Context.environment.variable('wildcard_qcpaws_certificate_nonp')
    end

    # Returns Production wildcard certificate name
    # @return [String] wildcard certificate name
    def prod_wildcard_qcpaws_certificate_name
      Context.environment.variable('wildcard_qcpaws_certificate_prod')
    end

    # Returns Production wildcard certificate name
    # @return [String] wildcard certificate name
    def verify_certificate_alias(certificateAlias:)
      certificateAlias.match('@([\w-]+\-[\w-]+)')
    end
  end
end
