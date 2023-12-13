require 'aws-sdk'
require 'digest'
require 'fileutils'

module S3Helper
  def _s3_helper_init(role = nil)
    @s3_client = nil
    @s3_role = role
  end

  def s3_put_object(bucket, key, data, metadata = {}, headers: {})
    raise ArgumentError, "Expected String for parameter 'bucket', but received #{bucket.class}" unless bucket.is_a? String
    raise ArgumentError, "Expecting bucket name for parameter 'bucket', but received an empty string" if bucket.empty?
    raise ArgumentError, "Expected String for parameter 'key', but received #{key.class}" unless key.is_a? String
    raise ArgumentError, "Expecting object key for parameter 'key', but received an empty string" if key.empty?
    raise ArgumentError, "Expected String for parameter 'data', but received #{data.class}" unless data.is_a? String

    Log.debug "Calculating SHA256 checksum and MD5 of data for object #{key}"
    checksum = Digest::SHA256.base64digest(data)
    md5sum = Digest::MD5.base64digest(data)
    metadata = metadata.merge({ checksum: checksum })

    return _s3_upload(bucket, key, data, metadata, md5sum, headers: headers)
  end

  def s3_upload_file(bucket, key, file_path, metadata = {}, headers: {})
    raise ArgumentError, "Expected String for parameter 'bucket', but received #{bucket.class}" unless bucket.is_a? String
    raise ArgumentError, "Expecting bucket name for parameter 'bucket', but received an empty string" if bucket.empty?
    raise ArgumentError, "Expected String for parameter 'key', but received #{key.class}" unless key.is_a? String
    raise ArgumentError, "Expecting object key for parameter 'key', but received an empty string" if key.empty?
    raise ArgumentError, "Invalid file path was provided" unless File.file? file_path

    Log.debug "Calculating SHA256 checksum and MD5 of data for object #{key}"
    checksum = Digest::SHA256.file(file_path).base64digest
    md5sum = Digest::MD5.file(file_path).base64digest
    metadata = metadata.merge({ checksum: checksum })

    return _s3_upload(bucket, key, File.open(file_path), metadata, md5sum, headers: headers)
  end

  def s3_get_object(bucket, key, version = nil)
    raise ArgumentError, "Expected String for parameter 'bucket', but received #{bucket.class}" unless bucket.is_a? String
    raise ArgumentError, "Expecting bucket name for parameter 'bucket', but received an empty string" if bucket.empty?
    raise ArgumentError, "Expected String for parameter 'key', but received #{key.class}" unless key.is_a? String
    raise ArgumentError, "Expecting object key for parameter 'key', but received an empty string" if key.empty?

    begin
      params = {
        bucket: bucket,
        key: key,
      }
      params[:version_id] = version unless version.nil?

      # Request the object from S3
      Log.debug "Retrieving object #{key.inspect} (version #{version.inspect}) from bucket #{bucket.inspect}"
      response = _s3_client.get_object(params)

      # Read the object data from the response
      data = response.body.read
    rescue => e
      raise "Failed to download object #{key.inspect} from S3 bucket #{bucket.inspect} - #{e}"
    end

    # Validate the checksum
    Log.debug "Computing SHA256 checksum of retrieved S3 data for key #{key}"
    checksum = Digest::SHA256.base64digest(data)
    raise "Checksum validation for S3 object #{key.inspect} has failed - no checksum metadata on object" unless response.metadata.has_key? 'checksum'
    raise "Checksum validation for S3 object #{key.inspect} has failed - checksum mismatch" if checksum != response.metadata['checksum']

    Log.debug "Checksum of S3 object #{key.inspect} in bucket #{bucket.inspect} has been validated"

    return data, response.version_id
  end

  def s3_download_object(bucket: nil, key: nil, local_filename: "file", validate: true)
    response = {}
    begin
      params = {
        bucket: bucket,
        key: key,
        response_target: local_filename,
      }

      # ensure local dir exists
      FileUtils.mkdir_p File.dirname(local_filename)

      # Request the object from S3
      Log.debug "Saving S3 object #{key.inspect} from bucket #{bucket.inspect} to #{local_filename.inspect}"
      response = _s3_client.get_object(params)
    rescue => e
      raise "Failed to download object #{key.inspect} from S3 bucket #{bucket.inspect} - #{e}"
    end

    if validate
      # Validate the checksum
      Log.debug "Computing SHA256 checksum of retrieved S3 data for key #{key}"
      checksum = Digest::SHA256.file(local_filename).base64digest
      if checksum == response.metadata['checksum']
        Log.debug "Checksum of S3 object #{key.inspect} in bucket #{bucket.inspect} has been validated"
      else
        begin
          File.delete(local_filename)
        rescue => e
          Log.warn "Failed to delete file #{local_filename} after s3_download_file failure"
        end
        raise "Checksum validation for S3 object #{key.inspect} download has failed - #{e}"
      end
    end
    return response
  end

  def s3_download_objects(bucket: nil, prefix: nil, local_path: "./", validate: true)
    downloaded_objects = []

    begin
      # Download files from S3
      keys = s3_list_objects(bucket: bucket, prefix: prefix)
      keys.each do |key|
        begin
          local_filename = key.sub(prefix, local_path)
          FileUtils.mkpath File.dirname(local_filename)

          AwsHelper.s3_download_object(
            bucket: bucket,
            key: key,
            local_filename: local_filename,
            validate: validate
          )
          downloaded_objects << key
        rescue => e
          Log.warn "#{e}"
        end
      end
    rescue => e
      Log.warn "Error while downloading S3 objects from \"#{bucket}/#{prefix}\" to #{local_path.inspect} - #{e}"
    end

    return downloaded_objects
  end

  def s3_delete_object(bucket, key, version = nil)
    raise ArgumentError, "Expected String for parameter 'bucket', but received #{bucket.class}" unless bucket.is_a? String
    raise ArgumentError, "Expecting bucket name for parameter 'bucket', but received an empty string" if bucket.empty?
    raise ArgumentError, "Expected String for parameter 'key', but received #{key.class}" unless key.is_a? String
    raise ArgumentError, "Expecting object key for parameter 'key', but received an empty string" if key.empty?

    begin
      params = {
        bucket: bucket,
        key: key,
      }
      params[:version_id] = version unless version.nil?

      # Request the object from S3
      Log.debug "Deleting object #{key.inspect} from bucket #{bucket.inspect}"
      response = _s3_client.delete_object(params)
    rescue => e
      raise "Failed to delete object #{key.inspect} from S3 bucket #{bucket.inspect}: #{e}"
    end

    return response.version_id
  end

  def s3_list_objects(bucket: nil, prefix: nil)
    Log.debug "Getting list of objects with prefix #{prefix.inspect} from bucket #{bucket.inspect}"

    begin
      keys = []
      response = _s3_client.list_objects(
        bucket: bucket,
        prefix: prefix,
      )

      keys = response.contents.map { |object| object.key }
      while response.next_page? do
        response = response.next_page
        keys = keys + response.contents.map { |object| object.key }
      end
    rescue => e
      Log.error "#{e}"
      raise
    end

    return keys
  end

  # Delete all objects recursively if objects count is more then 1000
  def s3_delete_objects(bucket, prefix)
    Log.debug "Deleting objects with prefix #{prefix.inspect} from bucket #{bucket.inspect}"
    objects = s3_list_objects(bucket: bucket, prefix: prefix).map { |k| { key: k } }

    Log.debug "Deleting S3 objects: #{objects.map { |object| object[:key] }}"
    while objects.count > 1000 do
      objects_to_delete = objects[0..999]
      _s3_client.delete_objects(
        bucket: bucket,
        delete: {
          objects: objects_to_delete
        }
      )
      # Flushing first 1000 objects
      objects_to_delete.clear
      objects = objects.drop(1000)
    end

    if !objects.empty?
      _s3_client.delete_objects(
        bucket: bucket,
        delete: {
          objects: objects
        }
      )
    end
  end

  def s3_copy_object(source_bucket, source_key, destination_bucket, destination_key)
    begin
      params = {
        acl: "bucket-owner-full-control",
        bucket: destination_bucket,
        key: destination_key,
        copy_source: "#{source_bucket}/#{source_key}",
        metadata_directive: "COPY",
        server_side_encryption: "AES256",
      }

      Log.debug "Copying S3 object from \"#{source_bucket}/#{source_key}\" to \"#{destination_bucket}/#{destination_key}\" with param #{params}"
      response = _s3_client.copy_object(params)
      Log.debug "Copy successful #{response}"
    rescue => e
      raise "Failed to copy object \"#{source_bucket}/#{source_key}\" to \"#{destination_bucket}/#{destination_key}\" - #{e}"
    end

    return response.version_id
  end

  def _s3_upload(bucket, key, data, metadata, md5sum, headers: {})
    begin
      params = {
        acl: "bucket-owner-full-control",
        bucket: bucket,
        key: key,
        body: data,
        content_md5: md5sum,
        server_side_encryption: 'AES256',
        metadata: metadata,
      }

      whitelisted_headers = ["cache_control", "content_encoding", "content_language", "content_type", "expires"]
      headers.delete_if { |k| !whitelisted_headers.include?(k.to_s) }
      params = headers.merge(params)

      Log.debug "Uploading object to S3 \"#{bucket}/#{key}\" with headers #{headers}"
      response = _s3_client.put_object(params)
      Log.debug "Upload successful, version = #{response.version_id.inspect}"
    rescue => e
      raise "Failed to upload #{key.inspect} to S3 bucket #{bucket.inspect}: #{e}"
    end

    return response.version_id
  end

  # Retrieve an S3 client
  def _s3_client
    @client_mutex.synchronize do
      # Create the S3 client if it doesn't yet exist
      if @s3_client.nil?
        Log.debug "Creating a new AWS S3 client"

        # Build the client parameters
        params = {}
        params[:region] = @region unless @region.nil?
        params[:retry_limit] = @retry_limit unless @retry_limit.nil?

        if @s3_role.nil?
          s3_role_credentials = nil
        else
          s3_role_credentials = sts_get_role_credentials(@s3_role)
        end

        credentials = s3_role_credentials || _control_credentials || nil
        params[:credentials] = credentials unless credentials.nil?
        @s3_client = Aws::S3::Client.new(params)
      end
    end

    return @s3_client
  end
end
