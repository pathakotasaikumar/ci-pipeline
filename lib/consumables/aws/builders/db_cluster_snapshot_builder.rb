module DbClusterSnapshotBuilder
  # Process specified snapshot_id parameter
  # Aliases such as latest and take-snapshot can be passed and acted on
  # Handles validation of snapshots
  # @param snapshot_id [String] Physical snapshot id
  # @param component_name [String] Name of the target component
  # @param resource_name [String] Target Logical Resource Name (MyDatabase)
  def _process_db_cluster_snapshot(
    snapshot_id:,
    component_name:,
    resource_name:
  )

    debug = Context.environment.variable('allow_missing_snapshot_target', false)
    build_number = Context.persist.released_build_number

    db_cluster_arn = Context.component.variable(component_name, "#{resource_name}Arn", nil, build_number)
    db_cluster = db_cluster_arn.gsub(/.*cluster:/, '') unless db_cluster_arn.nil?

    result_snapshot = case snapshot_id
                      when 'latest', '@latest'
                        _latest_db_cluster_snapshot(
                          component_name: component_name,
                          db_cluster: db_cluster
                        )
                      when '@take-snapshot', 'take-snapshot'
                        _take_db_cluster_snapshot(
                          component_name: component_name,
                          db_cluster: db_cluster
                        )
                      else
                        _validate_db_cluster_snapshot(
                          snapshot_id: snapshot_id,
                          component_name: component_name
                        )
                      end

    if result_snapshot.nil? || result_snapshot.empty?
      message = "WARNING: No valid RDS Cluster snapshots were identified from: #{component_name}.#{resource_name}"
      raise message if debug.to_s != 'true'

      Log.warn message
      Log.warn "-- Continuing the build with ('allow_missing_snapshot_target'=true)"
    end

    result_snapshot
  end

  # Find and validate the latest snapshot for the given DB Cluster
  # If found, validate if encrypted with correct key and re-encrypt if needed
  # @param component_name [String] Name of the component
  # @param db_cluster [String] Name of the DB cluster
  def _latest_db_cluster_snapshot(component_name:, db_cluster: nil)
    return nil if db_cluster.nil? || db_cluster.empty?

    Log.info "Querying snapshots for  #{db_cluster}"

    # Find and use the latest snapshot id
    candidate_snapshot_id = AwsHelper.rds_cluster_latest_snapshot(
      db_cluster: db_cluster
    )

    return nil if candidate_snapshot_id.nil?

    # Validate the snapshot, return new snapshot id if copied
    final_snapshot_id = AwsHelper.rds_validate_or_copy_db_cluster_snapshot(
      snapshot_identifier: candidate_snapshot_id,
      component_name: component_name,
      sections: default_section_variable,
      cmk_arn: Context.kms.secrets_key_arn
    )

    if final_snapshot_id != candidate_snapshot_id
      # Add snapshot to the list of temporary snapshots to be removed on teardown
      temp_snapshots = Context.component.variable(component_name, 'TempSnapshots', [])
      temp_snapshots << final_snapshot_id
      Context.component.set_variables(component_name, 'TempSnapshots' => temp_snapshots)
      Log.debug "Adding temporary snapshot #{final_snapshot_id} for removal on teardown"
    end

    return final_snapshot_id
  end

  # Attempt to take a snapshot from the released build
  # If successful, validate if encrypted with correct key and re-encrypt if needed
  # @param component_name [String] Name of the component
  # @param db_cluster [String] Name of the DB cluster
  # @return [String] Snapshot identifier
  def _take_db_cluster_snapshot(component_name:, db_cluster: nil)
    return nil if db_cluster.nil? || db_cluster.empty?

    Log.info "Taking a snapshot of #{component_name}.#{db_cluster}"

    snapshot_target_name = Defaults.snapshot_identifier(
      component_name: component_name
    )

    candidate_snapshot_id = AwsHelper.rds_cluster_create_snapshot(
      cluster_id: db_cluster,
      snapshot_identifier: snapshot_target_name,
      tags: Defaults.get_tags(component_name)
    )

    AwsHelper.rds_wait_for_cluster_snapshot(
      snapshot_identifier: candidate_snapshot_id,
      delay: 60,
      max_attempts: 480
    )

    # Validate the snapshot, return new snapshot id if copied
    final_snapshot_id = AwsHelper.rds_validate_or_copy_db_cluster_snapshot(
      snapshot_identifier: candidate_snapshot_id,
      component_name: component_name,
      sections: default_section_variable,
      cmk_arn: Context.kms.secrets_key_arn
    )

    # Add snapshot to the list of temporary snapshots to be removed on teardown
    temp_snapshots = Context.component.variable(component_name, 'TempSnapshots', [])
    temp_snapshots << final_snapshot_id
    Context.component.set_variables(component_name, 'TempSnapshots' => temp_snapshots)
    Log.debug "Adding temporary snapshot #{final_snapshot_id} for removal on teardown"

    Log.info "Completed and validated a new RDS Cluster Snapshot for #{db_cluster} - #{candidate_snapshot_id}"
    return final_snapshot_id
  rescue => e
    Log.error "Failed to execute snapshot on '#{component_name}' cluster "\
      "#{db_cluster} - #{snapshot_target_name} - #{e}"
    raise "Unable to execute action Snapshot - #{e}"
  ensure
    # delete the source snapshot which pipeline created
    if final_snapshot_id != candidate_snapshot_id
      AwsHelper.rds_delete_db_cluster_snapshots([candidate_snapshot_id]) unless candidate_snapshot_id.nil?
      Log.debug "Deleted temporary snapshot for '#{component_name}' - #{candidate_snapshot_id}"
    end
  end

  # Attempt to take a snapshot from the released build
  # If successful, validate if encrypted with correct key and re-encrypt if needed
  # @param component_name [String] Name of the component
  # @param snapshot_id [String] Name of the DB cluster
  # @return [String] Snapshot identifier
  def _validate_db_cluster_snapshot(snapshot_id:, component_name:)
    #  Simply validate the RDS snapshot
    final_snapshot_id = AwsHelper.rds_validate_or_copy_db_cluster_snapshot(
      snapshot_identifier: snapshot_id,
      component_name: component_name,
      sections: default_section_variable,
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

  # Process the snapshot id from the target branch
  # Handles validation of snapshots
  # @param snapshot_tags [Hash] Target snapshot values
  def _process_target_db_cluster_snapshot(snapshot_tags:)
    debug = Context.environment.variable('allow_missing_snapshot_target', false)

    unless snapshot_tags[:build].nil?
      db_cluster_arn = Context.component.variables(
        ase: snapshot_tags[:ase].downcase,
        build: snapshot_tags[:build],
        branch: snapshot_tags[:branch],
      )["#{snapshot_tags[:component]}.#{snapshot_tags[:resource]}Arn"]
    end

    db_cluster = db_cluster_arn.gsub(/.*cluster:/, '') unless db_cluster_arn.nil?

    result_snapshot = _latest_db_cluster_snapshot(
      component_name: snapshot_tags[:component],
      db_cluster: db_cluster
    )

    if result_snapshot.nil? || result_snapshot.empty?
      message = "WARNING: No valid Snapshot was identified from RDS Cluster '#{db_cluster_arn}'"
      raise message if debug.to_s != 'true'

      Log.warn message
      Log.warn "-- Continuing the build with ('allow_missing_snapshot_target'=true)"
    end
    result_snapshot
  end

  private

  # Default section variables method
  # @return (Hash)
  def default_section_variable
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
