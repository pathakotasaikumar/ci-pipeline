require 'aws-sdk'

module RdsHelper
  # Creates a DB Instance snapshot
  # @param db_instance [String] Database instance
  # @param snapshot_identifier [String] Snapshot identifier
  # @param tags [Hash] Tags to be added to the result snapshot
  def rds_instance_create_snapshot(db_instance:, snapshot_identifier:, tags: nil)
    params = {
      db_instance_identifier: db_instance,
      db_snapshot_identifier: snapshot_identifier
    }

    params[:tags] = tags unless tags.nil?

    Log.debug "Creating a new snapshot from DB instance - #{db_instance}"
    _rds_client.create_db_snapshot(params).db_snapshot.db_snapshot_identifier
  rescue => e
    Log.snow "ERROR: Failed to create RDS instance snapshot (DB Instace = #{db_instance})"
    raise "Failed to create RDS instance snapshot #{db_instance} - #{e}"
  end

  # Creates a DB Cluster snapshot
  # @param cluster_id [String] Cluster id
  # @param snapshot_identifier [String] Snapshot identifier
  # @param tags [Hash] List of tags to add to the snapshot
  # @return [String] Result snapshot id
  def rds_cluster_create_snapshot(cluster_id:, snapshot_identifier:, tags: nil)
    params = {
      db_cluster_identifier: cluster_id,
      db_cluster_snapshot_identifier: snapshot_identifier
    }

    params[:tags] = tags unless tags.nil?

    Log.debug "Creating a new snapshot for RDS Cluster #{cluster_id}"
    _rds_client.create_db_cluster_snapshot(params)
               .db_cluster_snapshot.db_cluster_snapshot_identifier
  rescue => e
    Log.snow "ERROR: Failed to create RDS cluster snapshot (DB Cluster = #{cluster_id})"
    raise "Failed to create RDS cluster snapshot #{cluster_id} - #{e}"
  end

  # Finds the latest instance snapshot for a given DB instance
  # @param db_instance [String] Database instance
  # @return [String] Snapshot identifier
  def rds_instance_latest_snapshot(db_instance:)
    Log.info("Querying for RDS snapshots")
    latest_snapshot = nil
    params = { db_instance_identifier: db_instance }

    marker = nil
    loop do
      params[:marker] = marker

      # Iterate over the many pages of possible results from the RDS API
      resp = _rds_client.describe_db_snapshots(params)
      marker = resp.marker

      resp.db_snapshots.each do |snapshot|
        if latest_snapshot.nil? || snapshot.snapshot_create_time > latest_snapshot.snapshot_create_time
          latest_snapshot = snapshot
        end
      end
      break if marker.nil? || marker.empty?
    end

    if latest_snapshot.nil?
      Log.debug("Unable to find a previous RDS snapshot")
    else
      Log.debug("Found snapshot #{latest_snapshot.db_snapshot_identifier.inspect} created on \"#{latest_snapshot.snapshot_create_time}\"")
      return latest_snapshot.db_snapshot_identifier
    end
  end

  # Finds the latest cluster snapshot for a given DB Cluster
  # @param db_cluster [String] Database cluster identifier
  # @return [String] Result snapshot identifier
  def rds_cluster_latest_snapshot(db_cluster:)
    Log.info("Querying for RDS Cluster snapshots")
    latest_snapshot = nil
    params = { db_cluster_identifier: db_cluster }

    marker = nil
    loop do
      params[:marker] = marker

      # Iterate over the many pages of possible results from the RDS API
      resp = _rds_client.describe_db_cluster_snapshots(params)
      marker = resp.marker

      resp.db_cluster_snapshots.each do |snapshot|
        if latest_snapshot.nil? || snapshot.snapshot_create_time > latest_snapshot.snapshot_create_time
          latest_snapshot = snapshot
        end
      end
      break if marker.nil? || marker.empty?
    end

    if latest_snapshot.nil?
      Log.debug("Unable to find a previous RDS snapshot")
    else
      Log.debug("Found snapshot #{latest_snapshot.db_cluster_snapshot_identifier.inspect} created on \"#{latest_snapshot.snapshot_create_time}\"")
      return latest_snapshot.db_cluster_snapshot_identifier
    end
  end

  # Wait for snapshot to reach status 'available'
  # @param snapshot_identifier [String] RDS physical snapshot id
  # @param max_attempts [Integer] Max number of attempts to query status
  # @param delay [Integer] Wait delay between each attempt
  def rds_wait_for_snapshot(
    snapshot_identifier:,
    max_attempts: 60,
    delay: 60
  )

    # Minimum of 1 attempt
    max_attempts = [1, max_attempts].max
    params = { db_snapshot_identifier: snapshot_identifier }

    (1..max_attempts).each do |attempt|
      response = _rds_client.describe_db_snapshots(params)
      # Snapshot doesn't exist
      if response.db_snapshots.nil? || response.db_snapshots.empty?
        raise "RDS Snapshot #{snapshot_identifier.inspect} does not exist"
      end

      current_status = response.db_snapshots.first.status
      Log.debug "RDS Snapshot #{snapshot_identifier.inspect} current status is"\
          " #{current_status} - percentage completed - #{response.db_snapshots.first.percent_progress}%"

      # Return if current_status is available
      return true if current_status == "available"

      sleep(delay) if attempt != max_attempts
    end

    raise "Timed out waiting for RDS Snapshot to available"
  end

  # Wait fora cluster snapshot to reach status 'available'
  # @param snapshot_identifier [String]  RDS physical cluster snapshot id
  # @param max_attempts [int] Max number of attempts to query status
  # @param delay [int] Wait delay between each attempt
  def rds_wait_for_cluster_snapshot(
    snapshot_identifier:,
    max_attempts: 60,
    delay: 60
  )

    # Minimum of 1 attempt
    max_attempts = [1, max_attempts].max
    params = { db_cluster_snapshot_identifier: snapshot_identifier }

    (1..max_attempts).each do |attempt|
      response = _rds_client.describe_db_cluster_snapshots(params)
      # Snapshot doesn't exist
      if response.db_cluster_snapshots.nil? || response.db_cluster_snapshots.empty?
        raise "RDS Cluster Snapshot #{snapshot_identifier.inspect} does not exist"
      end

      current_status = response.db_cluster_snapshots.first.status
      Log.debug "RDS Cluster Snapshot #{snapshot_identifier.inspect} current status"\
                " is #{current_status} - percentage completed - "\
                "#{response.db_cluster_snapshots.first.percent_progress}%"

      # Return if current_status is available
      return true if current_status == "available"

      sleep(delay) if attempt != max_attempts
    end

    raise "Timed out waiting for RDS Snapshot to become available"
  end

  # Query and return instance snapshot attributes
  # @param snapshot_identifier [String] Physical snapshot id
  # @return [Object] Snapshot attributes response object
  def rds_describe_snapshot_attributes(snapshot_identifier:)
    response = _rds_client.describe_db_snapshots(
      db_snapshot_identifier: snapshot_identifier
    )
    return response.db_snapshots.first
  rescue => e
    Log.snow "ERROR: Failed to Describe RDS snapshot (DB Snapshot id = #{snapshot_identifier})"
    raise "Failed to Describe RDS snapshot status #{snapshot_identifier} - #{e}"
  end

  # Query and return cluster snapshot attributes
  # @param snapshot_identifier [String] Physical snapshot id
  # @return [Object] Snapshot attributes response object
  def rds_describe_cluster_snapshot_attributes(snapshot_identifier:)
    response = _rds_client.describe_db_cluster_snapshots(
      db_cluster_snapshot_identifier: snapshot_identifier
    )
    return response.db_cluster_snapshots.first
  rescue => e
    Log.snow "ERROR: Failed to Describe RDS snapshot (DB Snapshot id = #{snapshot_identifier})"
    raise "Failed to Describe RDS snapshot status #{snapshot_identifier} - #{e}"
  end

  # Execute copy of RDS snapshot with optional re-encryption parameter
  # @param source_snapshot_identifier [String] Source physical snapshot id
  # @param copy_snapshot_identifier [String] Target name for the snapshot
  # @param kms_key_id [String] KMS CMK Arn to be used for encryption
  # @param tags [Hash] Key/Value pairs to be assigned as tags on the snapshot
  def rds_copy_db_instance_snapshot(
    source_snapshot_identifier:,
    copy_snapshot_identifier:,
    kms_key_id: nil,
    tags: nil
  )

    params = {
      source_db_snapshot_identifier: source_snapshot_identifier,
      target_db_snapshot_identifier: copy_snapshot_identifier
    }
    params[:kms_key_id] = kms_key_id unless kms_key_id.nil? || kms_key_id.empty?
    params[:tags] = tags unless tags.nil? || tags.empty?

    response = _rds_client.copy_db_snapshot(params)
    Log.debug "Initiated copy of '#{source_snapshot_identifier}' -> "\
      "new snapshot '#{copy_snapshot_identifier}' with cmk #{kms_key_id}"
    response.db_snapshot.db_snapshot_identifier
  rescue => e
    Log.snow "ERROR: Failed to create snapshot from source snapshot (DB snapshot = #{source_snapshot_identifier})"
    raise "Failed to create  snapshot #{source_snapshot_identifier} - #{e}"
  end

  # Execute copy of RDS snapshot with optional re-encryption parameter
  # @param source_snapshot_identifier [String] Source physical snapshot id
  # @param copy_snapshot_identifier [String] Target name for the snapshot
  # @param kms_key_id [String] KMS CMK Arn to be used for encryption
  # @param tags [Hash] Key/Value pairs to be assigned as tags on the snapshot
  def rds_copy_db_cluster_snapshot(
    source_snapshot_identifier:,
    copy_snapshot_identifier:,
    kms_key_id: nil,
    tags: nil
  )

    params = {
      source_db_cluster_snapshot_identifier: source_snapshot_identifier,
      target_db_cluster_snapshot_identifier: copy_snapshot_identifier
    }
    params[:kms_key_id] = kms_key_id unless kms_key_id.nil? || kms_key_id.empty?
    params[:tags] = tags unless tags.nil? || tags.empty?

    response = _rds_client.copy_db_cluster_snapshot(params)
    Log.debug "Initiated copy of '#{source_snapshot_identifier}' -> "\
      "new snapshot '#{copy_snapshot_identifier}' with cmk #{kms_key_id}"
    response.db_cluster_snapshot.db_cluster_snapshot_identifier
  rescue => e
    Log.snow "ERROR: Failed to create a copy snapshot from source cluster snapshot (DB snapshot = #{source_snapshot_identifier})"
    raise "Failed to create cluster snapshot #{source_snapshot_identifier} - #{e}"
  end

  # Validates if snapshot is correctly encrypted
  # Initiates snapshot copy with valid kms_key_id for re-encryption
  # @param snapshot_identifier [String] Physical snapshot id
  # @param component_name [String] Target component name
  def rds_validate_or_copy_db_cluster_snapshot(
    snapshot_identifier:,
    component_name:,
    sections:,
    cmk_arn: nil
  )

    aws_account_id = Context.environment.account_id

    params = {}
    params[:resource_name] = "arn:aws:rds:#{@region}:#{aws_account_id}:cluster-snapshot:#{snapshot_identifier.gsub(/.*cluster-snapshot:/, '')}"
    resp_tags = _rds_client.list_tags_for_resource(params)

    # Parse tags that have been received.
    tags = {}
    resp_tags.tag_list.each do |tag|
      tags[tag.key] = tag.value
    end

    raise "ERROR: Couldn't find tags on the snapshot #{snapshot_identifier.inspect}" if tags.empty?

    unless StringUtils.compare_upcase(tags['AMSID'], sections[:ams]) and
           StringUtils.compare_upcase(tags['EnterpriseAppID'], sections[:qda]) and
           StringUtils.compare_upcase(tags['ApplicationServiceID'], sections[:as])
      raise "ERROR: The Cluster Snapshot ID #{snapshot_identifier} does not belong"\
        " to the current Application Service ID #{sections[:qda].upcase}-#{sections[:as].upcase}"
    end
    raise "KMS key for application service #{Defaults.kms_secrets_key_alias} is not found." if cmk_arn.nil?

    snapshot_attributes = rds_describe_cluster_snapshot_attributes(
      snapshot_identifier: snapshot_identifier
    )

    if !snapshot_attributes.storage_encrypted
      Log.info "Component #{component_name} snapshot #{snapshot_identifier}"\
        " is encrypted NOT encrypted, returning the #{snapshot_identifier} to provision cluster DB"
      return snapshot_identifier
    elsif snapshot_attributes.storage_encrypted && cmk_arn == snapshot_attributes.kms_key_id
      Log.info "Component #{component_name} snapshot #{snapshot_identifier}"\
        " is encrypted with valid CMK - #{cmk_arn}"
      return snapshot_identifier
    end

    Log.info "Component #{component_name} snapshot #{snapshot_identifier} IS NOT"\
      " encrypted with the correct CMK: #{cmk_arn}"

    copy_snapshot_identifier = rds_copy_db_cluster_snapshot(
      source_snapshot_identifier: snapshot_identifier,
      copy_snapshot_identifier: "copysnapshot-#{Defaults.snapshot_identifier(component_name: component_name)}",
      kms_key_id: cmk_arn,
      tags: Defaults.get_tags(component_name)
    )

    Log.info "Successfully Created RDS Cluster '#{component_name}' snapshot"\
      " #{copy_snapshot_identifier} using CMK #{Defaults.kms_secrets_key_alias}"

    #  wait for snapshot to available
    rds_wait_for_cluster_snapshot(
      snapshot_identifier: copy_snapshot_identifier,
      delay: 60,
      max_attempts: 480
    )

    # Return the new RDS snapshot id with KMS key id
    copy_snapshot_identifier
  rescue => e
    Log.error "Failed to create an RDS cluster #{component_name} snapshot - #{e}"
    raise "Unable to execute action Snapshot for #{snapshot_identifier} - #{e}"
  end

  # Validates if snapshot is correctly encrypted
  # Initiates snapshot copy with valid kms_key_id for re-encryption
  # @param snapshot_identifier [String] Physical snapshot id
  # @param component_name [String] Target component name
  def rds_validate_or_copy_db_instance_snapshot(
    snapshot_identifier:,
    component_name:,
    sections:,
    cmk_arn: nil
  )

    aws_account_id = Context.environment.account_id
    raise "KMS key for application service #{Defaults.kms_secrets_key_alias} is not found." if cmk_arn.nil?

    params = {}
    params[:resource_name] = "arn:aws:rds:#{@region}:#{aws_account_id}:snapshot:#{snapshot_identifier.gsub(/.*snapshot:/, '')}"
    resp_tags = _rds_client.list_tags_for_resource(params)

    # Parse tags that have been received.
    tags = {}
    resp_tags.tag_list.each do |tag|
      tags[tag.key] = tag.value
    end

    raise "ERROR: Couldn't find tags on the snapshot #{snapshot_identifier.inspect}" if tags.empty?

    unless StringUtils.compare_upcase(tags['AMSID'], sections[:ams]) and
           StringUtils.compare_upcase(tags['EnterpriseAppID'], sections[:qda]) and
           StringUtils.compare_upcase(tags['ApplicationServiceID'], sections[:as])
      raise "ERROR: The Snapshot ID #{snapshot_identifier} does not belong"\
        " to the current Application Service ID #{sections[:qda].upcase}-#{sections[:as].upcase}"
    end

    snapshot_attributes = rds_describe_snapshot_attributes(
      snapshot_identifier: snapshot_identifier
    )

    if snapshot_attributes.encrypted && cmk_arn == snapshot_attributes.kms_key_id
      Log.info "Component #{component_name} snapshot #{snapshot_identifier}"\
      " is encrypted with valid CMK - #{cmk_arn}"
      return snapshot_identifier
    end

    copy_snapshot_name = "copysnapshot-#{Defaults.snapshot_identifier(component_name: component_name)}"
    copy_snapshot_identifier = rds_copy_db_instance_snapshot(
      source_snapshot_identifier: snapshot_identifier,
      copy_snapshot_identifier: copy_snapshot_name,
      kms_key_id: cmk_arn,
      tags: Defaults.get_tags(component_name)
    )

    Log.info "Successfully Created RDS instance '#{component_name}' snapshot "\
      " #{copy_snapshot_identifier} using CMK #{Defaults.kms_secrets_key_alias}"

    #  wait for snapshot to available
    rds_wait_for_snapshot(
      snapshot_identifier: copy_snapshot_identifier,
      delay: 60,
      max_attempts: 480
    )

    # Return the new RDS snapshot id with KMS key id
    copy_snapshot_identifier
  rescue => e
    Log.error "FAIL: Failed to execute Snapshot on #{component_name} - #{e}"
    raise "Unable to execute action Snapshot for #{component_name} - #{e}"
  end

  # Delete RDS Instance snapshots
  # @param snapshot_ids [Array] Physical snapshot id
  def rds_delete_db_instance_snapshots(snapshot_ids)
    raise ArgumentError, "Parameter 'snapshot_ids' is mandatory" if snapshot_ids.nil? or snapshot_ids.empty?

    Log.debug "Deleting snapshots #{snapshot_ids.inspect}"

    snapshot_ids.each do |snapshot_id|
      Log.debug "Deleting snapshot #{snapshot_id.inspect}"
      begin
        params = { db_snapshot_identifier: snapshot_id }
        _rds_client.delete_db_snapshot(params)
        Log.snow "Deleted snapshot (SnapshotId = #{snapshot_id.inspect})"
      rescue => e
        Log.snow "ERROR: Failed to delete snapshot (SnapshotId = #{snapshot_id.inspect})"
        raise "Failed to delete snapshot (SnapshotId = #{snapshot_id.inspect}) - #{e}"
      end
    end
  end

  # Delete RDS Cluster snapshots
  # @param snapshot_ids [Array] Physical snapshot id
  def rds_delete_db_cluster_snapshots(snapshot_ids)
    raise ArgumentError, "Parameter 'snapshot_ids' is mandatory" if snapshot_ids.nil? or snapshot_ids.empty?

    Log.debug "Deleting snapshots #{snapshot_ids.inspect}"

    snapshot_ids.each do |snapshot_id|
      Log.debug "Deleting snapshot #{snapshot_id.inspect}"
      begin
        params = { db_cluster_snapshot_identifier: snapshot_id }
        _rds_client.delete_db_cluster_snapshot(params)
        Log.snow "Deleted snapshot (SnapshotId = #{snapshot_id.inspect})"
      rescue => e
        Log.snow "ERROR: Failed to delete snapshot (SnapshotId = #{snapshot_id.inspect})"
        raise "Failed to delete snapshot (SnapshotId = #{snapshot_id.inspect}) - #{e}"
      end
    end
  end

  # @return [Object] Returns Aws::RDS::Client object
  def _rds_helper_init
    @rds_client = nil
  end

  # Wait for Instance or Cluster to reach status 'available'
  # @param component_name [String] Target component name
  # @param db_instance_identifier [String] The DB Instance identifier
  # @param db_cluster_identifier [String] The DB Cluster identifier
  # @param max_attempts [Integer] Max number of attempts to query status
  # @param delay [Integer] Wait delay between each attempt
  def rds_wait_for_status_available(
    component_name: nil,
    db_instance_identifier: nil,
    db_cluster_identifier: nil,
    max_attempts: 60,
    delay: 60
  )

    max_attempts = [1, max_attempts].max
    (1..max_attempts).each do |attempt|
      if db_instance_identifier
        response = _rds_client.describe_db_instances(
          db_instance_identifier: db_instance_identifier.gsub(/.*db:/, '')
        )
        current_status = response.db_instances.first.status
        Log.debug "RDS Instance #{db_instance_identifier} current status is #{current_status}"
      elsif db_cluster_identifier
        response = _rds_client.describe_db_clusters(
          db_cluster_identifier: db_cluster_identifier.gsub(/.*cluster:/, '')
        )
        current_status = response.db_clusters.first.status
        Log.debug "RDS Instance #{db_cluster_identifier} current status is #{current_status}"
      else
        raise "Either db_instance_identifier or db_cluster_identifier must be specified."
      end

      # Return if current_status is available
      return true if current_status == "available"

      sleep(delay) if attempt != max_attempts
    end
    raise "Timed out waiting for RDS Instance/Cluster to be available"
  rescue => e
    Log.error "ERROR: Failed to get RDS status (db_instance_identifier=#{db_instance_identifier} or db_cluster_identifier=#{db_cluster_identifier})"
    raise "Failed to get RDS status (db_instance_identifier=#{db_instance_identifier} or db_cluster_identifier=#{db_cluster_identifier}) - #{e.inspect}"
  end

  # Enable CopyTagsToSnapshot property on RDS DB instances or clusters
  # @param component_name [String] Target component name
  # @param db_instance_identifier [String] The DB Instance identifier
  # @param db_cluster_identifier [String] The DB Cluster identifier
  # @param copy_tags_to_snapshot [Boolean] Whether to copy all tags from the DB instance or cluster to snapshots
  def rds_enable_copy_tags_to_snapshot(
    component_name: nil,
    db_instance_identifier: nil,
    db_cluster_identifier: nil,
    copy_tags_to_snapshot: nil
  )
    if db_instance_identifier
      Log.output "Modifying CopyTagsToSnapshot property for :- #{component_name} and Identifier:- #{db_instance_identifier}"
      _rds_client.modify_db_instance(
        db_instance_identifier: db_instance_identifier.gsub(/.*db:/, ''),
        copy_tags_to_snapshot: copy_tags_to_snapshot,
        apply_immediately: true
      )
    elsif db_cluster_identifier
      Log.output "Modifying CopyTagsToSnapshot property for :- #{component_name} and Identifier:- #{db_cluster_identifier}"
      _rds_client.modify_db_cluster(
        db_cluster_identifier: db_cluster_identifier.gsub(/.*cluster:/, ''),
        copy_tags_to_snapshot: copy_tags_to_snapshot,
        apply_immediately: true
      )
    else
      raise "Either db_instance_identifier or db_cluster_identifier must be specified."
    end
  rescue => e
    Log.snow "ERROR: Failed to set RDS CopyTagsToSnapshot property (db_instance_identifier=#{db_instance_identifier} or db_cluster_identifier=#{db_cluster_identifier})"
    raise "Failed to set RDS CopyTagsToSnapshot property (db_instance_identifier=#{db_instance_identifier} or db_cluster_identifier=#{db_cluster_identifier}) - #{e.inspect}"
  end

  # Reset RDS password which restored from snapshot
  # @param db_instance_identifier [String] Physical snapshot id
  # @param db_cluster_identifier [String] Physical snapshot id
  # @param password [String] Hash encode value
  def rds_reset_password(
    db_instance_identifier: nil,
    db_cluster_identifier: nil,
    component_name: nil,
    password:
  )
    if db_instance_identifier
      Log.output "Re-setting Database password for the component name :- #{component_name} and Identifier:- #{db_instance_identifier}"
      _rds_client.modify_db_instance(
        db_instance_identifier: db_instance_identifier.gsub(/.*db:/, ''),
        master_user_password: password,
        apply_immediately: true
      )
    elsif db_cluster_identifier
      Log.output "Re-setting cluster Database password for the component name :- #{component_name} and Identifier:- #{db_cluster_identifier} "
      _rds_client.modify_db_cluster(
        db_cluster_identifier: db_cluster_identifier.gsub(/.*cluster:/, ''),
        master_user_password: password,
        apply_immediately: true
      )
    else
      raise "Either db_instance_identifier or db_cluster_identifier must be specified."
    end
  rescue => e
    Log.snow "ERROR: Failed to reset RDS password (db_instance_identifier=#{db_instance_identifier} or db_cluster_identifier=#{db_cluster_identifier})"
    raise "Failed to reset RDS password (db_instance_identifier=#{db_instance_identifier} or db_cluster_identifier=#{db_cluster_identifier}) - #{e.inspect}"
  end

  # Enable RDS Log exports to Cloudwatch logs
  # @param component_name [String] Target component name
  # @param db_instance_identifier [String] The DB Instance identifier
  # @param db_cluster_identifier [String] The DB Cluster identifier
  # @param enable_log_types [Array] Array of log types to enable sending to CW Logs

  def rds_enable_cloudwatch_logs_export(
    db_instance_identifier: nil,
    db_cluster_identifier: nil,
    component_name: nil,
    enable_log_types: nil
  )
    if db_instance_identifier
      Log.output "Enabling Cloudwatch Logs output for :- #{component_name} and Identifier:- #{db_instance_identifier}"
      _rds_client.modify_db_instance(
        db_instance_identifier: db_instance_identifier.gsub(/.*db:/, ''),
        cloudwatch_logs_export_configuration: {
          enable_log_types: enable_log_types
        },
        apply_immediately: true
      )
    elsif db_cluster_identifier
      Log.output "Enabling Cloudwatch Logs output for :- #{component_name} and Identifier:- #{db_cluster_identifier} "
      _rds_client.modify_db_cluster(
        db_cluster_identifier: db_cluster_identifier.gsub(/.*cluster:/, ''),
        cloudwatch_logs_export_configuration: {
          enable_log_types: enable_log_types
        },
        apply_immediately: true
      )
    else
      raise "Either db_instance_identifier or db_cluster_identifier must be specified."
    end
  rescue => e
    Log.snow "ERROR: Failed to set RDS cloudwatch logs export (db_instance_identifier=#{db_instance_identifier} or db_cluster_identifier=#{db_cluster_identifier})"
    raise "Failed to set RDS cloudwatch logs export (db_instance_identifier=#{db_instance_identifier} or db_cluster_identifier=#{db_cluster_identifier}) - #{e.inspect}"
  end

  def performanceinsight(definition,resource,kms_arn)
    performance_insights_enabled = JsonTools.get(definition, "Properties.EnablePerformanceInsights", false)
    if performance_insights_enabled
      JsonTools.transfer(definition, "Properties.EnablePerformanceInsights", resource, true)
      JsonTools.transfer(definition, "Properties.PerformanceInsightsKMSKeyId", resource, kms_arn)
      JsonTools.transfer(definition, "Properties.PerformanceInsightsRetentionPeriod", resource, 7)
    end
    return resource
  end
  # Retrieve a CloudFormation client
  private

  def _rds_client
    # Create a new client if it doesn't exist yet
    @client_mutex.synchronize do
      if @rds_client.nil?

        # Creat the CloudFormation client
        Log.debug "Creating a new RDS client"

        # Build the client parameters
        params = {}
        params[:http_proxy] = @proxy unless @proxy.nil?
        params[:region] = @region unless @region.nil?
        params[:retry_limit] = @retry_limit unless @retry_limit.nil?
        credentials = _provisioning_credentials || _control_credentials || nil
        params[:credentials] = credentials unless credentials.nil?

        @rds_client = Aws::RDS::Client.new(params)
      end
    end

    return @rds_client
  end
end
