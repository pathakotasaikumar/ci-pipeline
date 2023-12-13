require 'defaults/public_s3_content'

RSpec.describe Defaults::PublicS3Content do
  context 'public_s3_content_bucket' do
    it 'successfully return public bucket name' do
      if Defaults.sections[:env] == "prod"
        allow(Defaults).to receive(:public_s3_content_bucket).and_return("public_s3_content_bucket_prod")
      else
        allow(Defaults).to receive(:public_s3_content_bucket).and_return("public_s3_content_bucket_nonp")
      end
    end
  end

  context 'public_s3_content_upload_role' do
    it 'successfully return public bucket role' do
      if Defaults.sections[:env] == "prod"
        allow(Defaults).to receive(:public_s3_content_upload_role).and_return("public_s3_content_upload_role_prod")
      else
        allow(Defaults).to receive(:public_s3_content_upload_role).and_return("public_s3_content_upload_role_nonp")
      end
    end
  end
end
