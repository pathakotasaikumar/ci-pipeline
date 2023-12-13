require 'yaml'
require 'tmpdir'
require 'date'

class S3StateStorage
  def initialize(bucket, prefix = [])
    raise "Expected String for parameter 'bucket', but received #{bucket.class}" unless bucket.is_a? String
    raise "Expected Array for parameter 'prefix', but received #{prefix.class}" unless prefix.is_a? Array

    @bucket = bucket
    @prefix = prefix
  end

  def load(context_path)
    # TODO, should check if context_path is an array

    # Load the build context
    begin
      context_yaml, _version_id = AwsHelper.s3_get_object(@bucket, (@prefix + context_path).join('/'))
      variables = YAML.load(context_yaml, aliases: true, permitted_classes: [Date, Symbol])
    rescue StandardError => e
      Log.debug "Could not load context file for this build (may be a new build), using blank context instead - #{e}"
      variables = nil
    end

    variables
  end

  def save(context_path, variables)
    # TODO, should check if context_path is an array

    return if variables.nil?

    begin
      AwsHelper.s3_put_object(@bucket, (@prefix + context_path).join('/'), YAML.dump(variables))
    rescue StandardError => e
      Log.error "Failed to save the build context - #{e}"
    end
  end
end
