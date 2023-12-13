module Defaults
  module Veracode
    extend self

    # @return [String] Value for Veracode activation id
    def avos_release_arn
      Context.environment.variable('avos_release_arn', nil)
    end

    # @return [String] Optional AVOS invocation role
    def avos_invocation_role
      Context.environment.variable('avos_invocation_role', nil)
    end

    # @return [String] Name of the veracode bucket
    def avos_bucket_name
      Context.environment.variable('veracode_bucket_name', 'qcp-veracode-prod')
    end

    # @return [String] S3 Path where code artefacts should be uploaded
    def avos_artefact_prefix
      [
        sections[:ams],
        sections[:qda],
        sections[:as],
        sections[:branch],
        sections[:build]
      ].join('/')
    end

    # @return [String] App name for the application in veracode
    def avos_app_name
      "#{sections[:ams]}-#{sections[:qda]}-#{sections[:as]}"
    end

    # @return [String] Default Veracode artefact filename
    def avos_artefact_filename
      "scan.tar.gz"
    end
  end
end
