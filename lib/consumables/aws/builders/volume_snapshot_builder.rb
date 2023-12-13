module VolumeSnapshotBuilder
  # Process specified snapshot_id parameter
  # Aliases such as latest and take-snapshot can be passed and acted on
  # Handles validation of snapshots
  # @param snapshot_id [String] Physical snapshot id
  # @param component_name [String] Name of the target component
  # @param resource_name [String] Target volume resource
  def _process_volume_snapshot(
    snapshot_id:,
    component_name:,
    resource_name:
  )

    debug = Context.environment.variable('allow_missing_snapshot_target', false)
    build_number = Context.persist.released_build_number
    volume_id = Context.component.variable(component_name, "#{resource_name}Id", nil, build_number)

    unless build_number.nil?
      volume_name = _snapshot_name(
        build: build_number,
        component: component_name
      )
    end

    result_snapshot = case snapshot_id
                      when 'latest', '@latest'
                        _latest_volume_snapshot(
                          component_name: component_name,
                          volume_name: volume_name
                        )
                      when 'take-snapshot', '@take-snapshot'
                        _take_volume_snapshot(
                          component_name: component_name,
                          volume_id: volume_id
                        )
                      else
                        _validate_volume_snapshot(
                          snapshot_id: snapshot_id,
                          component_name: component_name
                        )
                      end

    if result_snapshot.nil?
      message = "WARNING: No valid EBS Volume Snapshot was identified from: #{snapshot_id}"
      raise message if debug.to_s != 'true'

      Log.warn message
      Log.warn "-- Continuing the build with ('allow_missing_snapshot_target'=true)"
    end

    result_snapshot
  end

  # Find and validate the latest snapshot for the given DB Instance
  # If found, validate if encrypted with correct key and re-encrypt if needed
  # @param component_name [String] Name of the component
  # @param volume_name [String] Name of the volume
  # @return [String] Snapshot identifier
  def _latest_volume_snapshot(component_name:, volume_name: nil)
    return nil if volume_name.nil? || volume_name.empty?

    Log.info "Looking up EBS snapshots for #{volume_name}"

    # Find and use the latest snapshot id
    candidate_snapshot_id = AwsHelper.ec2_latest_snapshot(
      volume_name: volume_name
    )

    return nil if candidate_snapshot_id.nil?

    # Validate the snapshot, return new snapshot id if copied
    final_snapshot_id = AwsHelper.ec2_validate_or_copy_snapshot(
      snapshot_id: candidate_snapshot_id,
      component_name: component_name,
      sections: default_volume_section_variable,
      cmk_arn: Context.kms.secrets_key_arn
    )

    if final_snapshot_id != candidate_snapshot_id
      # Add snapshot to the list of temporary snapshots to be removed on teardown
      temp_snapshots = Context.component.variable(component_name, 'TempSnapshots', [])
      temp_snapshots << final_snapshot_id
      Context.component.set_variables(component_name, 'TempSnapshots' => temp_snapshots)
      Log.debug "Adding temporary snapshot #{final_snapshot_id} for removal on teardown"
    end

    final_snapshot_id
  end

  # Attempt to take a snapshot from the releaed build
  # If successful, validate if encrypted with correct key and re-encrypt if needed
  # @param component_name [String] Name of the component
  # @param volume_id [String] target volume id
  # @return [String] Snapshot identifier
  def _take_volume_snapshot(component_name:, volume_id:)
    return nil if volume_id.nil? || volume_id.empty?

    Log.info "Taking a snapshot from #{component_name} - #{volume_id}"

    snapshot_name = Defaults.snapshot_identifier(
      component_name: component_name
    )

    candidate_snapshot_id = AwsHelper.ec2_create_volume_snapshot(
      volume_id: volume_id,
      description: snapshot_name,
      tags: Defaults.get_tags(component_name),
      check_volume_status: false
    )

    # Pause to ensure the snapshot is to be made available
    AwsHelper.ec2_wait_for_volume_snapshot(
      snapshot_id: candidate_snapshot_id,
      max_attempts: 480,
      delay: 60
    )

    Log.info "Created a new EBS snapshot for '#{component_name}' - #{candidate_snapshot_id}"

    # Validate the snapshot, return new snapshot id if copied
    final_snapshot_id = AwsHelper.ec2_validate_or_copy_snapshot(
      snapshot_id: candidate_snapshot_id,
      component_name: component_name,
      sections: default_volume_section_variable,
      cmk_arn: Context.kms.secrets_key_arn
    )

    # Add snapshot to the list of temporary snapshots to be removed on teardown
    temp_snapshots = Context.component.variable(component_name, 'TempSnapshots', [])
    temp_snapshots << final_snapshot_id
    Context.component.set_variables(component_name, 'TempSnapshots' => temp_snapshots)
    Log.debug "Adding temporary snapshot #{final_snapshot_id} for removal on teardown"

    Log.info "Completed and validated '#{component_name}' snapshot - #{final_snapshot_id}"
    return final_snapshot_id
  rescue => e
    raise "Failed to create '#{component_name}' snapshot - '#{snapshot_name}' - #{e}"
  ensure
    # delete the source snapshot which pipeline created
    if candidate_snapshot_id != final_snapshot_id
      AwsHelper.ec2_delete_snapshots [candidate_snapshot_id] unless candidate_snapshot_id.nil?
      Log.info "Deleting temporary snapshot for '#{component_name}' - #{candidate_snapshot_id}"
    end
  end

  # Validate if the given snapshot is encrypted with correct key and re-encrypt if needed
  # @param component_name [String] Name of the component
  # @param snapshot_id [String] Name of the DB instance
  # @return [String] Snapshot identifier
  def _validate_volume_snapshot(snapshot_id:, component_name:)
    #  Simply validate the RDS snapshot
    final_snapshot_id = AwsHelper.ec2_validate_or_copy_snapshot(
      snapshot_id: snapshot_id,
      component_name: component_name,
      sections: default_volume_section_variable,
      cmk_arn: Context.kms.secrets_key_arn
    )

    if final_snapshot_id != snapshot_id
      # Add snapshot to the list of temporary snapshots to be removed on teardown
      temp_snapshots = Context.component.variable(component_name, 'TempSnapshots', [])
      temp_snapshots << final_snapshot_id
      Context.component.set_variables(component_name, 'TempSnapshots' => temp_snapshots)
      Log.debug "Adding temporary snapshot #{final_snapshot_id} for removal on teardown"
    end

    return final_snapshot_id
  end

  # Process specified snapshot_id parameter
  # Aliases such as latest and take-snapshot can be passed and acted on
  # Handles validation of snapshots
  # @param snapshot_tags [Hash] Target snapshot values
  def _process_target_volume_snapshot(snapshot_tags:)
    debug = Context.environment.variable('allow_missing_snapshot_target', false)

    unless snapshot_tags[:build].nil?
      volume_name = _snapshot_name(
        ase: snapshot_tags[:ase].downcase,
        branch: snapshot_tags[:branch],
        build: snapshot_tags[:build],
        component: snapshot_tags[:component]
      )
    end

    result_snapshot = _latest_volume_snapshot(
      component_name: snapshot_tags[:component],
      volume_name: volume_name
    )

    if result_snapshot.nil?
      message = "WARNING: No valid EBS Volume Snapshot was identified from: #{volume_name.inspect}"
      raise message if debug.to_s != 'true'

      Log.warn message
      Log.warn "-- Continuing the build with ('allow_missing_snapshot_target'=true)"
    end

    result_snapshot
  end

  private

  # Function to create a snapshot name
  # @param sections [Hash]
  # @return (String)
  def _snapshot_name(**sections)
    sections = default_volume_section_variable.merge(sections)
    [
      sections[:ams],
      sections[:qda],
      sections[:as],
      sections[:ase].downcase,
      sections[:branch],
      sections[:build],
      sections[:component]
    ].join('-')
  end

  # Default section variables method
  # @return (Hash)
  def default_volume_section_variable
    sections = Defaults.sections
    {
      ams: sections[:ams],
      qda: sections[:qda],
      as: sections[:as],
      ase: sections[:ase],
      branch: sections[:branch],
      build: sections[:build]
    }
  end
end
