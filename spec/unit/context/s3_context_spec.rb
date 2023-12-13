$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib/context/"))
$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib/context/storage"))
require 's3_context.rb'
require 's3_state_storage.rb'
RSpec.describe S3Context do
  before(:context) do
  end

  context '.initialise' do
    it 'can create S3Context' do
      context = S3Context.new
    end
  end

  context '.pipeline_bucket_name' do
    it 'returns custom pipeline_bucket_name' do
      allow(Context).to receive_message_chain('component.variable')
        .with('pipeline', 'PipelineBucketName', nil)
        .and_return('custom-bucket-name')

      context = S3Context.new
      expect(context.pipeline_bucket_name).to eq('custom-bucket-name')
    end

    it 'returns default pipeline_bucket_name' do
      context = S3Context.new
      expect(context.pipeline_bucket_name).to eq(Defaults.pipeline_bucket_name)
    end

    it 'returns nil pipeline_bucket_name' do
      allow(Context).to receive_message_chain('component.variable').with('pipeline', 'PipelineBucketName', nil).and_return(nil)
      context = S3Context.new
      expect(context.pipeline_bucket_name).to eq(nil)
    end
  end

  context '.pipeline_bucket_arn' do
    it 'returns nil pipeline_bucket_arn' do
      allow(Context).to receive_message_chain('component.variable')
        .with('pipeline', 'PipelineBucketName', nil)
        .and_return(nil)

      context = S3Context.new
      expect(context.pipeline_bucket_arn).to eq(nil)
    end

    it 'returns default pipeline_bucket_arn' do
      context = S3Context.new
      expect(context.pipeline_bucket_arn).to eq("arn:aws:s3:::" + Defaults.pipeline_bucket_name)
    end
  end

  context '.artefact_bucket_arn' do
    it 'returns nil artefact_bucket_arn' do
      allow(Context).to receive_message_chain('component.variable')
        .with('pipeline', 'ArtefactBucketName', nil)
        .and_return(nil)

      context = S3Context.new
      expect(context.artefact_bucket_arn).to eq(nil)
    end

    it 'returns default artefact_bucket_arn' do
      context = S3Context.new
      expect(context.artefact_bucket_arn).to eq("arn:aws:s3:::" + Defaults.artefact_bucket_name)
    end
  end

  context '.legacy_bucket_arn' do
    it 'returns nil legacy_bucket_arn' do
      allow(Context).to receive_message_chain('component.variable')
        .with('pipeline', 'LegacyBucketName', nil)
        .and_return(nil)

      context = S3Context.new
      expect(context.legacy_bucket_arn).to eq(nil)
    end

    it 'returns default legacy_bucket_arn' do
      context = S3Context.new
      expect(context.legacy_bucket_arn).to eq("arn:aws:s3:::" + Defaults.legacy_bucket_name)
    end
  end

  context '.secret_bucket_arn' do
    it 'returns nil secret_bucket_arn' do
      allow(Context).to receive_message_chain('component.variable')
        .with('platform', 'SecretBucketName', nil)
        .and_return(nil)

      context = S3Context.new
      expect(context.secret_bucket_arn).to eq(nil)
    end

    it 'returns default secret_bucket_arn' do
      context = S3Context.new
      expect(context.secret_bucket_arn).to eq("arn:aws:s3:::" + Defaults.secrets_bucket_name)
    end
  end

  context '.lambda_artefact_bucket_arn' do
    it 'returns nil lambda_artefact_bucket_arn' do
      allow(Context).to receive_message_chain('component.variable')
        .with('pipeline', 'LambdaArtefactBucketName', nil)
        .and_return(nil)

      context = S3Context.new
      expect(context.lambda_artefact_bucket_arn).to eq(nil)
    end

    it 'returns default lambda_artefact_bucket_arn' do
      context = S3Context.new
      expect(context.lambda_artefact_bucket_arn).to eq("arn:aws:s3:::" + Defaults.lambda_artefact_bucket_name)
    end
  end

  context '.ams_bucket_arn' do
    it 'returns nil ams_bucket_arn' do
      allow(Context).to receive_message_chain('component.variable')
        .with('pipeline', 'AmsBucketName', nil)
        .and_return(nil)

      context = S3Context.new
      expect(context.ams_bucket_arn).to eq(nil)
    end

    it 'returns default ams_bucket_arn' do
      context = S3Context.new
      # bucket-ams-test coming from spec_helper
      expect(context.ams_bucket_arn).to eq("arn:aws:s3:::" + "bucket-ams-test")
    end
  end

  context '.qda_bucket_arn' do
    it 'returns nil qda_bucket_arn' do
      allow(Context).to receive_message_chain('component.variable')
        .with('pipeline', 'QdaBucketName', nil)
        .and_return(nil)

      context = S3Context.new
      expect(context.qda_bucket_arn).to eq(nil)
    end

    it 'returns default qda_bucket_arn' do
      context = S3Context.new
      # bucket-qda-test coming from spec_helper
      expect(context.qda_bucket_arn).to eq("arn:aws:s3:::" + "bucket-qda-test")
    end
  end
end # RSpec.describe
