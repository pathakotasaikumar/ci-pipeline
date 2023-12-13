require 'aws-sdk'
require 'base64'

module KmsHelper
  def _kms_helper_init
    @kms_client = nil
  end

  def kms_resolve_alias(kms_cmk_alias)
    raise ArgumentError, "Parameter 'kms_cmk_alias' is mandatory" if kms_cmk_alias.nil? or kms_cmk_alias.empty?

    begin
      params = {}
      params[:key_id] = kms_cmk_alias

      response = _kms_client.describe_key(params)

      kms_cmk_arn = response.key_metadata.arn
    rescue Aws::KMS::Errors::NotFoundException => e
      # Trap this an let the function return nil
      kms_cmk_arn = nil
    rescue => e
      raise ActionError.new(), "An error occurred while resolving a KMS alias to its key - #{e}"
    end

    return kms_cmk_arn
  end

  def kms_create_alias(kms_cmk_arn, kms_cmk_alias)
    raise ArgumentError, "Parameter 'kms_cmk_arn' is mandatory" if kms_cmk_arn.nil? or kms_cmk_arn.empty?
    raise ArgumentError, "Parameter 'kms_cmk_alias' is mandatory" if kms_cmk_alias.nil? or kms_cmk_alias.empty?

    begin
      # Check to see if the alias already resolves in this account
      kms_alias_key = kms_resolve_alias(kms_cmk_alias)
      if kms_alias_key.nil?
        # Alias doesn't exist - create
        Log.info "Creating KMS key alias #{kms_cmk_alias.inspect} => #{kms_cmk_arn.inspect}"
        response = _kms_client.create_alias(alias_name: kms_cmk_alias, target_key_id: kms_cmk_arn)
      elsif kms_alias_key != kms_cmk_arn
        # Alias exists but is pointing at wrong key - update
        Log.info "Updating KMS key alias #{kms_cmk_alias.inspect} => #{kms_cmk_arn.inspect}"
        response = _kms_client.update_alias(alias_name: kms_cmk_alias, target_key_id: kms_cmk_arn)
      else
        # Alias exists
        Log.debug "Not creating KMS key alias as it is already assoicated to '#{kms_alias_key}'"
      end
    rescue => e
      raise ActionError.new(), "An error occurred while creating a KMS alias - #{e}"
    end
  end

  def kms_encrypt_data(cmk, plaintext)
    Log.info("Encrypting #{plaintext.size} bytes with KMS CMK key #{cmk.inspect}")

    params = {
      key_id: cmk,
      plaintext: plaintext,
    }
    resp = _kms_client.encrypt(params)
    ciphertext = resp.ciphertext_blob
    base64_ciphertext = Base64.strict_encode64(ciphertext)

    return base64_ciphertext
  end

  def kms_decrypt_data(base64_ciphertext)
    ciphertext = Base64.decode64(base64_ciphertext)
    Log.info("Decrypting #{ciphertext.size} bytes using KMS CMK key")

    params = {
      ciphertext_blob: ciphertext,
    }
    resp = _kms_client.decrypt(params)
    key_id = resp.key_id
    plaintext = resp.plaintext

    Log.debug("Successfully decrypted #{plaintext.size} bytes using KMS CMK #{key_id.inspect}")

    return plaintext
  end

  def kms_generate_data_key_set(cmk)
    Log.info("Generating new Data Key from #{cmk}")

    params = {
      key_id: cmk,
      key_spec: "AES_256",
    }
    resp = _kms_client.generate_data_key(params)

    Log.debug("Encrypted key size: #{resp.ciphertext_blob.size} bytes")
    Log.debug("Plaintext key size: #{resp.plaintext.size} bytes")
    Log.debug("Data Key CMK ID: #{resp.key_id}")

    return resp
  end

  def kms_encrypt_data_local(key, blob)
    Log.info("Encrypting data (#{blob.size} bytes) locally...")

    alg = "AES-256-CBC"
    iv = OpenSSL::Cipher::Cipher.new(alg).random_iv
    cipher = OpenSSL::Cipher::Cipher.new(alg)

    cipher.encrypt
    cipher.iv = iv
    cipher.key = key

    ciphertext = cipher.update(blob)
    ciphertext << cipher.final

    # TODO - Write output to temp file to not exhaust memory
    # TODO - Ref: https://github.com/aws/aws-sdk-ruby/blob/master/aws-sdk-resources/lib/aws-sdk-resources/services/s3/encryption/io_encrypter.rb

    return Base64.encode64(ciphertext).split("\n") * "", Base64.encode64(iv)
  end

  def kms_decrypt_data_local(key, iv, blob)
    Log.info("Decrypting data (#{blob.size} bytes) locally...")

    alg = "AES-256-CBC"
    cipher = OpenSSL::Cipher::Cipher.new(alg)

    cipher.decrypt
    cipher.iv = Base64.decode64(iv)
    cipher.key = key

    plaintext = cipher.update(Base64.decode64(blob))
    plaintext << cipher.final

    # TODO - Write output to temp file to not exhaust memory
    # TODO - Ref: https://github.com/aws/aws-sdk-ruby/blob/master/aws-sdk-resources/lib/aws-sdk-resources/services/s3/encryption/io_decrypter.rb

    return plaintext
  end

  # Retrieve a KMS client
  private def _kms_client
    # Create a new client if it doesn't exist yet
    @client_mutex.synchronize do
      if @kms_client.nil?

        # Create the KMS client
        Log.debug "Creating a new AWS KMS client"

        # Build the client parameters
        params = {}
        params[:http_proxy] = @proxy unless @proxy.nil?
        params[:region] = @region unless @region.nil?
        params[:retry_limit] = @retry_limit unless @retry_limit.nil?

        if _provisioning_credentials
          # We have specific provisioning credentials to use
          params[:credentials] = _provisioning_credentials
        elsif _control_credentials
          # No provisioning credentials but we do have control credentials to use
          params[:credentials] = _control_credentials
        end

        @kms_client = Aws::KMS::Client.new(params)
      end
    end

    return @kms_client
  end
end
