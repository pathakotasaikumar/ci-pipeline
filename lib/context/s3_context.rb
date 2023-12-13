class S3Context
  def initialize
  end

  # Pipeline Bucket
  def set_pipeline_bucket_details(name)
    Context.component.set_variables("pipeline", {
      "PipelineBucketName" => name,
    })
  end

  def pipeline_bucket_name
    return Context.component.variable("pipeline", "PipelineBucketName", nil)
  end

  def pipeline_bucket_arn
    return nil if pipeline_bucket_name.nil?

    return "arn:aws:s3:::#{pipeline_bucket_name}"
  end

  # Legacy bucket
  def set_legacy_bucket_details(name)
    Context.component.set_variables("pipeline", {
      "LegacyBucketName" => name,
    })
  end

  # Secret bucket
  def set_secret_bucket_details(name)
    Context.component.set_variables("platform", {
      "SecretBucketName" => name,
    })
  end

  def legacy_bucket_name
    return Context.component.variable("pipeline", "LegacyBucketName", nil)
  end

  def legacy_bucket_arn
    return nil if legacy_bucket_name.nil?

    return "arn:aws:s3:::#{legacy_bucket_name}"
  end

  def secret_bucket_name
    return Context.component.variable("platform", "SecretBucketName", nil)
  end

  def secret_bucket_arn
    return nil if secret_bucket_name.nil?

    return "arn:aws:s3:::#{secret_bucket_name}"
  end

  # Artifact bucket
  def set_artefact_bucket_details(name)
    Context.component.set_variables("pipeline", {
      "ArtefactBucketName" => name,
    })
  end

  # Lambda Artifact bucket
  def set_lambda_artefact_bucket_details(name)
    Context.component.set_variables("pipeline", {
      "LambdaArtefactBucketName" => name,
    })
  end

  def artefact_bucket_name
    return Context.component.variable("pipeline", "ArtefactBucketName", nil)
  end

  def lambda_artefact_bucket_name
    return Context.component.variable("pipeline", "LambdaArtefactBucketName", nil)
  end

  def artefact_bucket_arn
    return nil if artefact_bucket_name.nil?

    return "arn:aws:s3:::#{artefact_bucket_name}"
  end

  def lambda_artefact_bucket_arn
    return nil if lambda_artefact_bucket_name.nil?

    return "arn:aws:s3:::#{lambda_artefact_bucket_name}"
  end

  # AMS Bucket
  def set_ams_bucket_details(name)
    Context.component.set_variables("pipeline", {
      "AmsBucketName" => name,
    })
  end

  def ams_bucket_name
    return Context.component.variable("pipeline", "AmsBucketName", nil)
  end

  def ams_bucket_arn
    return nil if ams_bucket_name.nil?

    return "arn:aws:s3:::#{ams_bucket_name}"
  end

  # QDA Bucket
  def set_qda_bucket_details(name)
    Context.component.set_variables("pipeline", {
      "QdaBucketName" => name,
    })
  end

  def qda_bucket_name
    return Context.component.variable("pipeline", "QdaBucketName", nil)
  end

  def qda_bucket_arn
    return nil if qda_bucket_name.nil?

    return "arn:aws:s3:::#{qda_bucket_name}"
  end

  # App Bucket
  def set_as_bucket_details(name)
    Context.component.set_variables("pipeline", {
      "AppBucketName" => name,
    })
  end

  def as_bucket_name
    return Context.component.variable("pipeline", "AppBucketName", nil)
  end

  def as_bucket_arn
    return nil if as_bucket_name.nil?

    return "arn:aws:s3:::#{as_bucket_name}"
  end

  def flush
    # Nothing to do - automatically flushed on every save
  end
end
