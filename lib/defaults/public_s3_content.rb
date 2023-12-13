module Defaults
  module PublicS3Content
    extend self

    # @return [String] Value for Public S3 Content
    def public_s3_content_bucket
      if Defaults.sections[:env] == "prod"
        Context.environment.variable('public_s3_content_bucket_prod', nil)
      else
        Context.environment.variable('public_s3_content_bucket_nonp', nil)
      end
    end

    # @return [String] Value for Public S3 Content Upload Role
    def public_s3_content_upload_role
      if Defaults.sections[:env] == "prod"
        Context.environment.variable('public_s3_content_upload_role_prod', nil)
      else
        Context.environment.variable('public_s3_content_upload_role_nonp', nil)
      end
    end

    # @return [String] Value for Public S3 Content approved applications
    def public_s3_content_approved_apps
      Context.environment.variable('public_s3_content_approved_apps', nil)
    end
  end
end
