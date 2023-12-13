require "action"
class Snapshot < Action
  def initialize(component: nil, params: nil, stage: nil, step: nil)
    super
    raise ArgumentError, "Action Snapshot does not accept parameters" unless (params == nil || params.empty?)
  end

  # @param (See Action#valid_stages)
  def valid_stages
    %w(
      PostDeploy
      PreRelease
      PostRelease
      PreTeardown
    )
  end

  # @param (See Action#valid_components)
  def valid_components
    %w(
      aws/volume
      aws/rds-mysql
      aws/rds-postgresql
      aws/rds-sqlserver
      aws/rds-oracle
      aws/rds-aurora
      aws/rds-aurora-postgresql
    )
  end

  # Executes Snapshot action against the target component
  def invoke
    snapshot_id = case @component.type
                  when 'aws/volume'
                    snapshot_volume
                  when 'aws/rds-mysql', 'aws/rds-oracle', 'aws/rds-postgresql', 'aws/rds-sqlserver'
                    snapshot_rds_instance
                  when 'aws/rds-aurora', 'aws/rds-aurora-postgresql'
                    snapshot_rds_cluster
                  else
                    raise "Unable to action Snapshot for component #{@component.type}"
                  end

    Log.output "SUCCESS: Executed Snapshot on #{@component.component_name} - #{snapshot_id}"

    temp_snapshots = Context.component.variable(@component.component_name, 'TempSnapshots', [])
    temp_snapshots << snapshot_id
    Context.component.set_variables(@component.component_name, 'TempSnapshots' => temp_snapshots)
    Log.debug "Adding temporary snapshot #{snapshot_id} for removal on teardown"
  rescue => e
    Log.error "FAIL: Failed to execute Snapshot on #{@component.component_name} - #{e}"
    raise "Unable to execute action Snapshot - #{e}"
  end

  private

  # Creates snapshot of EBS volume
  # @return [String] Snapshot ID of created snapshot
  def snapshot_volume
    volume = @component.volume.keys.first
    volume_id = Context.component.variable(
      @component.component_name, "#{volume}Id", nil
    )

    AwsHelper.ec2_create_volume_snapshot(
      volume_id: volume_id,
      description: Defaults.snapshot_identifier(component_name: @component.component_name),
      tags: Defaults.get_tags(@component.component_name)
    )
  end

  # Creates snapshot of EBS volume
  # @return [String] Snapshot ID of created snapshot
  def snapshot_rds_instance
    db_instance_arn = Context.component.variable(
      @component.component_name, "#{@component.db_instances.keys.first}Arn", nil
    )

    db_instance = db_instance_arn.gsub(/.*db:/, '')

    AwsHelper.rds_instance_create_snapshot(
      db_instance: db_instance,
      snapshot_identifier: Defaults.snapshot_identifier(
        component_name: @component.component_name
      )
    )
  end

  # Creates snapshot of EBS volume
  # @return [String] Snapshot ID of created snapshot
  def snapshot_rds_cluster
    cluster_id = Context.component.variable(
      @component.component_name,
      "#{@component.db_cluster.keys.first}Arn",
      nil
    ).gsub(/.*cluster:/, '')

    AwsHelper.rds_cluster_create_snapshot(
      cluster_id: cluster_id,
      snapshot_identifier: Defaults.snapshot_identifier(
        component_name: @component.component_name
      ),
      tags: Defaults.get_tags(@component.component_name)
    )
  end
end
