$LOAD_PATH.unshift("#{BASE_DIR}/lib/aws_helpers")
require 'rds_helper'
require 'json'
describe 'RdsHelper' do
  before(:context) do
    @dummy_class = DummyClass.new
    @dummy_class.extend(RdsHelper)
    @kms_key_id = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
  end

  context 'rds_create_snapshot' do
    it 'successful execution' do
      allow(AwsHelper).to receive(:_provisioning_credentials)
      allow(AwsHelper).to receive(:_control_credentials)

      dummy_client = double(Aws::RDS::Client)
      allow(AwsHelper).to receive(:_rds_client).and_return(dummy_client)

      mock_response = double(Object)
      allow(dummy_client).to receive(:create_db_snapshot).and_return(mock_response)

      mock_snapshot = double(Object)
      allow(mock_response).to receive(:db_snapshot).and_return(mock_snapshot)

      allow(mock_snapshot).to receive(:db_snapshot_identifier).and_return('dummy-snapshot-id')
      expect {
        AwsHelper.rds_instance_create_snapshot(
          db_instance: 'dummy_replication_group_id',
          snapshot_identifier: 'dummy_snapshot_id',
          tags: [{ key: 'Name', value: 'dummy' }]
        )
      }.not_to raise_exception
    end

    it 'failed with Failed to create volume snapshot' do
      allow(AwsHelper).to receive(:_provisioning_credentials)
      allow(AwsHelper).to receive(:_control_credentials)

      dummy_client = double(Aws::RDS::Client)
      allow(AwsHelper).to receive(:_rds_client).and_return(dummy_client)
      allow(dummy_client).to receive(:create_db_snapshot).and_raise(StandardError)
      expect {
        AwsHelper.rds_instance_create_snapshot(
          db_instance: 'dummy_replication_group_id',
          snapshot_identifier: 'dummy_snapshot_id',
          tags: [{ key: 'Name', value: 'dummy' }]
        )
      }.to raise_exception /Failed to create RDS instance snapshot/
    end

    it 'failed with ArgumentError' do
      allow(AwsHelper).to receive(:_provisioning_credentials)
      allow(AwsHelper).to receive(:_control_credentials)

      expect {
        AwsHelper.rds_instance_create_snapshot(
          db_instance: nil,
          snapshot_identifier: 'dummy_snapshot_id',
          tags: [{ key: 'Name', value: 'dummy' }]
        )
      }.to raise_exception RuntimeError
    end
  end

  context 'rds_cluster_create_snapshot' do
    it 'successful execution' do
      dummy_client = double(Aws::RDS::Client)
      allow(AwsHelper).to receive(:_rds_client).and_return(dummy_client)

      mock_response = double(Object)
      allow(dummy_client).to receive(:create_db_cluster_snapshot).and_return(mock_response)

      mock_snapshot = double(Object)
      allow(mock_response).to receive(:db_cluster_snapshot).and_return(mock_snapshot)

      allow(mock_snapshot).to receive(:db_cluster_snapshot_identifier).and_return('dummy-snapshot-id')
      expect {
        AwsHelper.rds_cluster_create_snapshot(
          cluster_id: 'dummy_replication_group_id',
          snapshot_identifier: 'dummy_snapshot_id',
          tags: [{ key: 'Name', value: 'dummy' }]
        )
      }.not_to raise_exception
    end

    it 'failed with Failed to create volume snapshot' do
      dummy_client = double(Aws::RDS::Client)
      allow(AwsHelper).to receive(:_rds_client).and_return(dummy_client)
      allow(dummy_client).to receive(:create_db_cluster_snapshot).and_raise(StandardError)
      expect {
        AwsHelper.rds_cluster_create_snapshot(
          cluster_id: 'dummy_replication_group_id',
          snapshot_identifier: 'dummy_snapshot_id',
          tags: [{ key: 'Name', value: 'dummy' }]
        )
      }.to raise_exception /Failed to create RDS cluster snapshot/
    end

    it 'failed with ArgumentError' do
      expect {
        AwsHelper.rds_cluster_create_snapshot(
          cluster_id: nil,
          snapshot_identifier: 'dummy_snapshot_id',
          tags: [{ key: 'Name', value: 'dummy' }]
        )
      }.to raise_exception RuntimeError
    end
  end

  context 'rds_instance_latest_snapshot' do
    it 'successful execution' do
      dummy_client = double(Aws::RDS::Client)
      allow(AwsHelper).to receive(:_rds_client).and_return(dummy_client)

      mock_response = double(Object)
      allow(dummy_client).to receive(:describe_db_snapshots).and_return(mock_response)

      mock_marker = double(Object)
      allow(mock_marker).to receive(:empty?).and_return(true)
      allow(mock_response).to receive(:marker).and_return(mock_marker)

      mock_snapshot = double(Object)
      allow(mock_response).to receive(:db_snapshots).and_return([mock_snapshot])
      allow(Context).to receive_message_chain(:environment, :account_id)
      allow(mock_snapshot).to receive(:db_snapshot_identifier).and_return('dummy-snapshot-id')
      allow(mock_snapshot).to receive(:snapshot_create_time).and_return('dummy-create-time')

      expect { AwsHelper.rds_instance_latest_snapshot(db_instance: 'dummy-instance') }
        .not_to raise_exception
    end

    it 'successful execution with nil' do
      dummy_client = double(Aws::RDS::Client)
      allow(AwsHelper).to receive(:_rds_client).and_return(dummy_client)

      mock_response = double(Object)
      allow(dummy_client).to receive(:describe_db_snapshots).and_return(mock_response)

      mock_marker = double(Object)
      allow(mock_marker).to receive(:empty?).and_return(true)
      allow(mock_response).to receive(:marker).and_return(mock_marker)

      mock_snapshot = double(Object)
      allow(mock_response).to receive(:db_snapshots).and_return({})
      allow(Context).to receive_message_chain(:environment, :account_id)
      allow(mock_snapshot).to receive(:db_snapshot_identifier).and_return(nil)
      allow(mock_snapshot).to receive(:snapshot_create_time).and_return('dummy-create-time')

      expect { AwsHelper.rds_instance_latest_snapshot(db_instance: 'dummy-instance') }
        .not_to raise_exception
    end
  end

  context 'rds_cluster_latest_snapshot' do
    it 'successful execution' do
      dummy_client = double(Aws::RDS::Client)
      allow(AwsHelper).to receive(:_rds_client).and_return(dummy_client)

      mock_response = double(Object)
      allow(dummy_client).to receive(:describe_db_cluster_snapshots).and_return(mock_response)

      mock_marker = double(Object)
      allow(mock_marker).to receive(:empty?).and_return(true)
      allow(mock_response).to receive(:marker).and_return(mock_marker)

      mock_snapshot = double(Object)
      allow(mock_response).to receive(:db_cluster_snapshots).and_return([mock_snapshot])
      allow(Context).to receive_message_chain(:environment, :account_id)
      allow(mock_snapshot).to receive(:db_cluster_snapshot_identifier).and_return('dummy-snapshot-id')
      allow(mock_snapshot).to receive(:snapshot_create_time).and_return('dummy-create-time')

      expect { AwsHelper.rds_cluster_latest_snapshot(db_cluster: 'dummy-instance') }
        .not_to raise_exception
    end

    it 'successful execution with none returned' do
      dummy_client = double(Aws::RDS::Client)
      allow(AwsHelper).to receive(:_rds_client).and_return(dummy_client)

      mock_response = double(Object)
      allow(dummy_client).to receive(:describe_db_cluster_snapshots).and_return(mock_response)

      mock_marker = double(Object)
      allow(mock_marker).to receive(:empty?).and_return(true)
      allow(mock_response).to receive(:marker).and_return(mock_marker)

      mock_snapshot = double(Object)
      allow(mock_response).to receive(:db_cluster_snapshots).and_return([])
      allow(Context).to receive_message_chain(:environment, :account_id)
      allow(mock_snapshot).to receive(:db_cluster_snapshot_identifier).and_return('dummy-snapshot-id')
      allow(mock_snapshot).to receive(:snapshot_create_time).and_return('dummy-create-time')

      expect { AwsHelper.rds_cluster_latest_snapshot(db_cluster: 'dummy-instance') }
        .not_to raise_exception
    end
  end

  context '_rds_client' do
    it 'successful execution - initialize no provisioning or control credentials' do
      allow(Aws::RDS::Client).to receive(:new)
      allow(AwsHelper).to receive(:_provisioning_credentials)
      allow(AwsHelper).to receive(:_control_credentials)
      expect { AwsHelper.send(:_rds_client) }.not_to raise_exception
    end

    it 'successful execution - initialize with provisioning credentials' do
      allow(Aws::RDS::Client).to receive(:new)
      mock_credentials = double(Object)
      allow(AwsHelper).to receive(:_provisioning_credentials).and_return(mock_credentials)
      allow(AwsHelper).to receive(:_control_credentials)
      expect { AwsHelper.send(:_rds_client) }.not_to raise_exception
    end

    it 'successful execution - initialize with control credentials' do
      allow(Aws::RDS::Client).to receive(:new)
      mock_credentials = double(Object)
      allow(AwsHelper).to receive(:_provisioning_credentials)
      allow(AwsHelper).to receive(:_control_credentials).and_return(mock_credentials)
      expect { AwsHelper.send(:_rds_client) }.not_to raise_exception
    end
  end

  # context 'rds_delete_instance_snapshot' do
  #
  #   it 'successful delete rds_cluster snapshot' do
  #     client = double(Aws::RDS::Client)
  #
  #     allow(AwsHelper).to receive(:_rds_client).and_return(client)
  #     allow(client).to receive(:delete_db_snapshot).and_return("successful")
  #
  #     expect {
  #       AwsHelper.rds_delete_instance_snapshot(snapshot_id: "test")
  #     }.not_to raise_exception
  #   end
  #
  #   it 'fails with Failed to delete snapshot' do
  #     client = double(Aws::RDS::Client)
  #
  #     allow(AwsHelper).to receive(:_rds_client).and_return(client)
  #     allow(client).to receive(:delete_db_snapshot).and_raise(RuntimeError)
  #
  #     expect {
  #       AwsHelper.rds_delete_instance_snapshot(snapshot_id: "test")
  #     }.to raise_exception /Failed to delete snapshot/
  #   end
  # end

  # context 'delete_db_cluster_snapshot' do
  #   it 'successful delete rds_cluster snapshot' do
  #     client = double(Aws::RDS::Client)
  #
  #     allow(AwsHelper).to receive(:_rds_client).and_return(client)
  #      allow(client).to receive(:delete_db_cluster_snapshot).and_return("successful")
  #
  #     expect {
  #       AwsHelper.rds_delete_cluster_snapshot(snapshot_id: "test")
  #     }.not_to raise_exception
  #   end
  #
  #   it 'fails with Failed to delete snapshot' do
  #     client = double(Aws::RDS::Client)
  #
  #     allow(AwsHelper).to receive(:_rds_client).and_return(client)
  #     allow(client).to receive(:delete_db_cluster_snapshot).and_raise(RuntimeError)
  #
  #     expect {
  #       AwsHelper.rds_delete_cluster_snapshot(snapshot_id: "test")
  #     }.to raise_exception /Failed to delete snapshot/
  #   end
  # end

  context 'rds_enable_cloudwatch_logs_export' do
    it 'succeeds' do
      client = double(Aws::RDS::Client)
      allow(@dummy_class).to receive(:_rds_client).and_return(client)
      allow(client).to receive(:modify_db_instance)
      allow(client).to receive(:modify_db_cluster)

      expect {
        @dummy_class.rds_enable_cloudwatch_logs_export(
          db_cluster_identifier: nil,
          db_instance_identifier: "test123",
          component_name: "test"
        )
      }.not_to raise_exception

      expect {
        @dummy_class.rds_enable_cloudwatch_logs_export(
          db_cluster_identifier: "test123",
          db_instance_identifier: nil,
          component_name: "test"
        )
      }.not_to raise_exception
    end

    it 'fails with RuntimeError' do
      client = double(Aws::RDS::Client)
      allow(@dummy_class).to receive(:_rds_client).and_return(client)

      expect {
        @dummy_class.rds_enable_cloudwatch_logs_export(
          db_cluster_identifier: nil,
          db_instance_identifier: nil,
          component_name: "test"
        )
      }.to raise_exception(RuntimeError, /Either db_instance_identifier or db_cluster_identifier must be specified./)
    end
  end

  context 'rds_wait_for_status_available' do
    it 'succeeds' do
      client = double(Aws::RDS::Client)
      response_msg = double(Object)
      db_instance = double(Object)
      db_instances_array = []
      db_instances_array << db_instance
      allow(db_instance).to receive(:status) .and_return("available")
      db_cluster = double(Object)
      db_clusters_array = []
      db_clusters_array << db_cluster
      allow(db_cluster).to receive(:status) .and_return("available")

      allow(@dummy_class).to receive(:_rds_client).and_return(client)
      allow(client).to receive(:describe_db_instances).and_return(response_msg)
      allow(response_msg).to receive(:db_instances) .and_return(db_instances_array)

      allow(client).to receive(:describe_db_clusters).and_return(response_msg)
      allow(response_msg).to receive(:db_clusters) .and_return(db_clusters_array)

      expect(
        @dummy_class.rds_wait_for_status_available(
          component_name: "test",
          db_instance_identifier: "test123"
        )
      ).to eq(true)

      expect(
        @dummy_class.rds_wait_for_status_available(
          component_name: "test",
          db_cluster_identifier: "test123"
        )
      ).to eq(true)
    end

    it 'test timeout issue' do
      client = double(Aws::RDS::Client)
      response_msg = double(Object)
      db_instance = double(Object)
      db_instances_array = []
      db_instances_array << db_instance
      allow(db_instance).to receive(:status) .and_return("upgrading")
      allow(@dummy_class).to receive(:_rds_client).and_return(client)
      allow(client).to receive(:describe_db_instances).and_return(response_msg)
      allow(response_msg).to receive(:db_instances) .and_return(db_instances_array)

      expect {
        @dummy_class.rds_wait_for_status_available(
          component_name: "test",
          db_instance_identifier: "test123",
          max_attempts: 2,
          delay: 0.05
        )
      } .to raise_error(RuntimeError, /Timed out waiting for RDS Instance\/Cluster to be available/)
    end

    it 'fails with RuntimeError' do
      client = double(Aws::RDS::Client)
      allow(@dummy_class).to receive(:_rds_client).and_return(client)

      expect {
        @dummy_class.rds_wait_for_status_available(
          component_name: "test",
          db_instance_identifier: nil,
          db_cluster_identifier: nil
        )
      }.to raise_exception(RuntimeError, /Either db_instance_identifier or db_cluster_identifier must be specified./)
    end
  end

  context 'rds_enable_copy_tags_to_snapshot' do
    it 'succeeds' do
      client = double(Aws::RDS::Client)
      allow(@dummy_class).to receive(:_rds_client).and_return(client)
      allow(client).to receive(:modify_db_instance)
      allow(client).to receive(:modify_db_cluster)

      expect {
        @dummy_class.rds_enable_copy_tags_to_snapshot(
          component_name: "test",
          db_instance_identifier: "test123",
          copy_tags_to_snapshot: true
        )
      }.not_to raise_exception

      expect {
        @dummy_class.rds_enable_copy_tags_to_snapshot(
          component_name: "test",
          db_cluster_identifier: "test123",
          copy_tags_to_snapshot: true
        )
      }.not_to raise_exception
    end

    it 'fails with RuntimeError' do
      client = double(Aws::RDS::Client)
      allow(@dummy_class).to receive(:_rds_client).and_return(client)

      expect {
        @dummy_class.rds_enable_copy_tags_to_snapshot(
          component_name: "test",
          db_instance_identifier: nil,
          db_cluster_identifier: nil
        )
      }.to raise_exception(RuntimeError, /Either db_instance_identifier or db_cluster_identifier must be specified./)
    end
  end

  context 'rds_copy_db_instance_snapshot'  do
    it 'test rds_copy_db_instance_snapshot snapshot' do
      client = double(Aws::RDS::Client)
      copySnapshotResponse = double(Aws::RDS::Types::CopyDBSnapshotResult)
      db_snapshot = double(Aws::RDS::Types::DBSnapshot, :db_snapshot_identifier => "copysnapshot-test")
      allow(@dummy_class).to receive(:_rds_client).and_return(client)
      allow(client).to receive(:copy_db_snapshot).and_return(copySnapshotResponse)
      allow(copySnapshotResponse).to receive(:db_snapshot).and_return(db_snapshot)

      expect(
        @dummy_class.rds_copy_db_instance_snapshot(
          source_snapshot_identifier: "test",
          copy_snapshot_identifier: "copysnapshot-test",
          kms_key_id: @kms_key_id
        )
      ).to eq("copysnapshot-test")
    end

    it 'test failure rds_copy_db_instance_snapshot snapshot' do
      client = double(Aws::RDS::Client)
      copySnapshotResponse = double(Aws::RDS::Types::CopyDBSnapshotResult)
      db_snapshot = double(Aws::RDS::Types::DBSnapshot, :db_snapshot_identifier => "copysnapshot-test")
      allow(@dummy_class).to receive(:_rds_client).and_return(client)
      allow(client).to receive(:copy_db_snapshot).and_return(RuntimeError)
      allow(copySnapshotResponse).to receive(:db_snapshot).and_return(db_snapshot)

      expect {
        @dummy_class.rds_copy_db_instance_snapshot(
          source_snapshot_identifier: "test",
          copy_snapshot_identifier: "copysnapshot-test",
          kms_key_id: @kms_key_id
        )
      }.to raise_error /Failed to create  snapshot test/
    end
  end

  context 'rds_copy_cluster_snapshot'  do
    it 'test rds_copy_cluster_snapshot snapshot' do
      client = double(Aws::RDS::Client)
      copyClusterSnapshotResponse = double(Aws::RDS::Types::CopyDBClusterSnapshotResult)
      db_cluster_snapshot = double(Aws::RDS::Types::DBClusterSnapshot, :db_cluster_snapshot_identifier => "copysnapshot-cluster-test")
      allow(@dummy_class)
        .to receive(:_rds_client)
        .and_return(client)

      allow(client)
        .to receive(:copy_db_cluster_snapshot)
        .and_return(copyClusterSnapshotResponse)

      allow(copyClusterSnapshotResponse)
        .to receive(:db_cluster_snapshot)
        .and_return(db_cluster_snapshot)
      expect(@dummy_class.rds_copy_db_cluster_snapshot(source_snapshot_identifier: "test", copy_snapshot_identifier: "copysnapshot-cluster-test", kms_key_id: @kms_key_id)).to eq("copysnapshot-cluster-test")
    end

    it 'test failed rds_copy_cluster_snapshot snapshot' do
      client = double(Aws::RDS::Client)
      copyClusterSnapshotResponse = double(Aws::RDS::Types::CopyDBClusterSnapshotResult)
      db_cluster_snapshot = double(Aws::RDS::Types::DBClusterSnapshot, :db_cluster_snapshot_identifier => "copysnapshot-cluster-test")
      allow(@dummy_class)
        .to receive(:_rds_client)
        .and_return(client)

      allow(client)
        .to receive(:copy_db_cluster_snapshot)
        .and_raise(RuntimeError)

      allow(copyClusterSnapshotResponse)
        .to receive(:db_cluster_snapshot)
        .and_return(db_cluster_snapshot)
      expect {
        @dummy_class.rds_copy_db_cluster_snapshot(
          source_snapshot_identifier: "test",
          copy_snapshot_identifier: "copysnapshot-cluster-test",
          kms_key_id: @kms_key_id
        )
      }.to raise_error(/Failed to create cluster/)
    end
  end

  context 'rds_describe_snapshot_attributes'  do
    it 'test rds_describe_snapshot_attributes snapshot' do
      client = double(Aws::RDS::Client)
      db_snapshot_message = double(Object)
      db_snapshot_1 = double(Aws::RDS::Types::DBSnapshot)
      db_snapshot_2 = double(Aws::RDS::Types::DBSnapshot)
      db_snapshot_3 = double(Aws::RDS::Types::DBSnapshot)
      db_snapshots_array = [db_snapshot_1, db_snapshot_2]
      db_snapshots_array2 = [db_snapshot_3]

      allow(@dummy_class).to receive(:_rds_client).and_return(client)
      allow(client).to receive(:describe_db_snapshots).and_return(db_snapshot_message)
      allow(db_snapshot_message).to receive(:db_snapshots).and_return(db_snapshots_array, db_snapshots_array2)

      expect(@dummy_class.rds_describe_snapshot_attributes(snapshot_identifier: "test")).to eq(db_snapshots_array[0])
    end

    it 'fails rds_describe_snapshot_attributes snapshot' do
      client = double(Aws::RDS::Client)

      allow(@dummy_class).to receive(:_rds_client).and_return(client)
      allow(client).to receive(:describe_db_snapshots).and_raise RuntimeError

      expect {
        @dummy_class.rds_describe_snapshot_attributes(snapshot_identifier: "test")
      }.to raise_exception /Failed to Describe RDS snapshot status/
    end
  end

  context 'rds_describe_snapshot_attributes' do
    it 'test rds_describe_cluster_snapshot_attributes snapshot' do
      client = double(Aws::RDS::Client)
      db_cluster_snapshot_message = double(Object)
      db_cluster_snapshot_1 = double(Aws::RDS::Types::DBClusterSnapshot)
      db_cluster_snapshot_2 = double(Aws::RDS::Types::DBClusterSnapshot)
      db_cluster_snapshot_3 = double(Aws::RDS::Types::DBClusterSnapshot)
      db_cluster_snapshots_array = [db_cluster_snapshot_1, db_cluster_snapshot_2]
      db_cluster_snapshots_array2 = [db_cluster_snapshot_3]

      allow(@dummy_class).to receive(:_rds_client).and_return(client)
      allow(client).to receive(:describe_db_cluster_snapshots).and_return(db_cluster_snapshot_message)
      allow(db_cluster_snapshot_message).to receive(:db_cluster_snapshots).and_return(db_cluster_snapshots_array, db_cluster_snapshots_array2)

      expect(
        @dummy_class.rds_describe_cluster_snapshot_attributes(snapshot_identifier: "test")
      ).to eq(db_cluster_snapshots_array[0])
    end

    it 'fails rds_describe_cluster_snapshot_attributes snapshot' do
      client = double(Aws::RDS::Client)

      allow(@dummy_class).to receive(:_rds_client).and_return(client)
      allow(client).to receive(:describe_db_cluster_snapshots).and_raise RuntimeError

      expect {
        @dummy_class.rds_describe_cluster_snapshot_attributes(snapshot_identifier: "test")
      }.to raise_exception /Failed to Describe RDS snapshot status/
    end
  end

  context 'rds_validate_or_copy_db_cluster_snapshot' do
    it 'return the same snapshot id if snapshot encrypted and with same cmk key' do
      dummy_client = double(Aws::RDS::Client)
      allow(AwsHelper).to receive(:_rds_client).and_return(dummy_client)

      allow(Context).to receive_message_chain('environment.account_id').and_return('123456789')

      mock_tags_response = double(Object)
      allow(dummy_client).to receive(:list_tags_for_resource).and_return(mock_tags_response)

      mock_tag_ams = double(Object)
      allow(mock_tag_ams).to receive(:key).and_return('AMSID')
      allow(mock_tag_ams).to receive(:value).and_return('AMS01')
      mock_tag_qda = double(Object)
      allow(mock_tag_qda).to receive(:key).and_return('EnterpriseAppID')
      allow(mock_tag_qda).to receive(:value).and_return('C031')
      mock_tag_as = double(Object)
      allow(mock_tag_as).to receive(:key).and_return('ApplicationServiceID')
      allow(mock_tag_as).to receive(:value).and_return('99')
      mock_tag_ase = double(Object)
      allow(mock_tag_ase).to receive(:key).and_return('Environment')
      allow(mock_tag_ase).to receive(:value).and_return('DEV')
      mock_tag_branch = double(Object)
      allow(mock_tag_branch).to receive(:key).and_return('Branch')
      allow(mock_tag_branch).to receive(:value).and_return('master')

      allow(mock_tags_response).to receive(:tag_list).and_return(
        [mock_tag_ams, mock_tag_qda, mock_tag_as, mock_tag_ase, mock_tag_branch]
      )

      allow(Context).to receive_message_chain('kms.secrets_key_arn').and_return('dummy-kms-key')
      describe_snapshot_response = double(Object)
      allow(AwsHelper).to receive(:rds_describe_cluster_snapshot_attributes).and_return(describe_snapshot_response)
      allow(describe_snapshot_response).to receive(:storage_encrypted).and_return(true)
      allow(describe_snapshot_response).to receive(:kms_key_id).and_return('dummy-kms-key')

      sections = { ams: 'ams01', qda: 'c031', as: '99', branch: 'master', ase: 'dev', build: '05' }
      expect(
        AwsHelper.rds_validate_or_copy_db_cluster_snapshot(
          snapshot_identifier: "snapshot",
          component_name: "Test-Component",
          sections: sections,
          cmk_arn: 'dummy-kms-key'
        )
      ).to eq('snapshot')
    end

    it 'return the same snapshot id if the snapshot is unecrypted' do
      dummy_client = double(Aws::RDS::Client)
      allow(AwsHelper).to receive(:_rds_client).and_return(dummy_client)

      allow(Context).to receive_message_chain('environment.account_id').and_return('123456789')

      mock_tags_response = double(Object)
      allow(dummy_client).to receive(:list_tags_for_resource).and_return(mock_tags_response)

      mock_tag_ams = double(Object)
      allow(mock_tag_ams).to receive(:key).and_return('AMSID')
      allow(mock_tag_ams).to receive(:value).and_return('AMS01')
      mock_tag_qda = double(Object)
      allow(mock_tag_qda).to receive(:key).and_return('EnterpriseAppID')
      allow(mock_tag_qda).to receive(:value).and_return('C031')
      mock_tag_as = double(Object)
      allow(mock_tag_as).to receive(:key).and_return('ApplicationServiceID')
      allow(mock_tag_as).to receive(:value).and_return('99')
      mock_tag_ase = double(Object)
      allow(mock_tag_ase).to receive(:key).and_return('Environment')
      allow(mock_tag_ase).to receive(:value).and_return('DEV')
      mock_tag_branch = double(Object)
      allow(mock_tag_branch).to receive(:key).and_return('Branch')
      allow(mock_tag_branch).to receive(:value).and_return('master')

      allow(mock_tags_response).to receive(:tag_list).and_return(
        [mock_tag_ams, mock_tag_qda, mock_tag_as, mock_tag_ase, mock_tag_branch]
      )

      allow(Context).to receive_message_chain('kms.secrets_key_arn').and_return('dummy-kms-key')
      describe_snapshot_response = double(Object)
      allow(AwsHelper).to receive(:rds_describe_cluster_snapshot_attributes).and_return(describe_snapshot_response)
      allow(describe_snapshot_response).to receive(:storage_encrypted).and_return(false)
      allow(describe_snapshot_response).to receive(:kms_key_id).and_return('dummy-key-id')
      allow(AwsHelper).to receive(:rds_copy_db_cluster_snapshot).and_return('dummy-copy-snapshot-id')
      allow(Defaults).to receive(:snapshot_identifier)
      allow(Defaults).to receive(:get_tags)
      allow(AwsHelper).to receive(:rds_wait_for_cluster_snapshot)

      sections = { ams: 'ams01', qda: 'c031', as: '99', branch: 'master', ase: 'dev', build: '05' }
      expect(
        AwsHelper.rds_validate_or_copy_db_cluster_snapshot(
          snapshot_identifier: "snapshot",
          component_name: "Test-Component",
          sections: sections,
          cmk_arn: 'dummy-kms-key'
        )
      ).to eq('snapshot')
    end

    it 'return the copysnapshot id if the snapshot is encrypted with different key' do
      dummy_client = double(Aws::RDS::Client)
      allow(AwsHelper).to receive(:_rds_client).and_return(dummy_client)

      allow(Context).to receive_message_chain('environment.account_id').and_return('123456789')

      mock_tags_response = double(Object)
      allow(dummy_client).to receive(:list_tags_for_resource).and_return(mock_tags_response)

      mock_tag_ams = double(Object)
      allow(mock_tag_ams).to receive(:key).and_return('AMSID')
      allow(mock_tag_ams).to receive(:value).and_return('AMS01')
      mock_tag_qda = double(Object)
      allow(mock_tag_qda).to receive(:key).and_return('EnterpriseAppID')
      allow(mock_tag_qda).to receive(:value).and_return('C031')
      mock_tag_as = double(Object)
      allow(mock_tag_as).to receive(:key).and_return('ApplicationServiceID')
      allow(mock_tag_as).to receive(:value).and_return('99')
      mock_tag_ase = double(Object)
      allow(mock_tag_ase).to receive(:key).and_return('Environment')
      allow(mock_tag_ase).to receive(:value).and_return('DEV')
      mock_tag_branch = double(Object)
      allow(mock_tag_branch).to receive(:key).and_return('Branch')
      allow(mock_tag_branch).to receive(:value).and_return('master')

      allow(mock_tags_response).to receive(:tag_list).and_return(
        [mock_tag_ams, mock_tag_qda, mock_tag_as, mock_tag_ase, mock_tag_branch]
      )

      allow(Context).to receive_message_chain('kms.secrets_key_arn').and_return('dummy-kms-key')
      describe_snapshot_response = double(Object)
      allow(AwsHelper).to receive(:rds_describe_cluster_snapshot_attributes).and_return(describe_snapshot_response)
      allow(describe_snapshot_response).to receive(:storage_encrypted).and_return(true)
      allow(describe_snapshot_response).to receive(:kms_key_id).and_return('other-key-id')
      allow(AwsHelper).to receive(:rds_copy_db_cluster_snapshot).and_return('dummy-copy-snapshot-id')
      allow(Defaults).to receive(:snapshot_identifier)
      allow(Defaults).to receive(:get_tags)
      allow(AwsHelper).to receive(:rds_wait_for_cluster_snapshot)
      sections = { ams: 'ams01', qda: 'c031', as: '99', branch: 'master', ase: 'dev', build: '05' }
      expect(
        AwsHelper.rds_validate_or_copy_db_cluster_snapshot(
          snapshot_identifier: "snapshot",
          component_name: "Test-Component",
          sections: sections,
          cmk_arn: 'dummy-kms-key'
        )
      ).to eq('dummy-copy-snapshot-id')
    end

    it 'fails with - KMS key for application service ... ' do
      allow(Context).to receive_message_chain("kms.secrets_key_arn").and_return(nil)

      dummy_client = double(Aws::RDS::Client)
      allow(AwsHelper).to receive(:_rds_client).and_return(dummy_client)

      allow(Context).to receive_message_chain('environment.account_id').and_return('123456789')

      mock_tags_response = double(Object)
      allow(dummy_client).to receive(:list_tags_for_resource).and_return(mock_tags_response)

      mock_tag_ams = double(Object)
      allow(mock_tag_ams).to receive(:key).and_return('AMSID')
      allow(mock_tag_ams).to receive(:value).and_return('AMS01')
      mock_tag_qda = double(Object)
      allow(mock_tag_qda).to receive(:key).and_return('EnterpriseAppID')
      allow(mock_tag_qda).to receive(:value).and_return('C031')
      mock_tag_as = double(Object)
      allow(mock_tag_as).to receive(:key).and_return('ApplicationServiceID')
      allow(mock_tag_as).to receive(:value).and_return('99')
      mock_tag_ase = double(Object)
      allow(mock_tag_ase).to receive(:key).and_return('Environment')
      allow(mock_tag_ase).to receive(:value).and_return('DEV')
      mock_tag_branch = double(Object)
      allow(mock_tag_branch).to receive(:key).and_return('Branch')
      allow(mock_tag_branch).to receive(:value).and_return('master')

      allow(mock_tags_response).to receive(:tag_list).and_return(
        [mock_tag_ams, mock_tag_qda, mock_tag_as, mock_tag_ase, mock_tag_branch]
      )
      sections = { ams: 'ams01', qda: 'c031', as: '99', branch: 'master', ase: 'dev', build: '05' }
      expect {
        AwsHelper.rds_validate_or_copy_db_cluster_snapshot(
          snapshot_identifier: "snapshot",
          component_name: "Test-Component",
          sections: sections
        )
      }.to raise_error RuntimeError, /KMS key for application service/
    end

    it 'fails with - incorrect application service id ... ' do
      allow(Context).to receive_message_chain("kms.secrets_key_arn").and_return('dummy-kms-key')

      dummy_client = double(Aws::RDS::Client)
      allow(AwsHelper).to receive(:_rds_client).and_return(dummy_client)

      allow(Context).to receive_message_chain('environment.account_id').and_return('123456789')

      mock_tags_response = double(Object)
      allow(dummy_client).to receive(:list_tags_for_resource).and_return(mock_tags_response)

      mock_tag_ams = double(Object)
      allow(mock_tag_ams).to receive(:key).and_return('AMSID')
      allow(mock_tag_ams).to receive(:value).and_return('AMS01')
      mock_tag_qda = double(Object)
      allow(mock_tag_qda).to receive(:key).and_return('EnterpriseAppID')
      allow(mock_tag_qda).to receive(:value).and_return('C036')
      mock_tag_as = double(Object)
      allow(mock_tag_as).to receive(:key).and_return('ApplicationServiceID')
      allow(mock_tag_as).to receive(:value).and_return('99')
      mock_tag_ase = double(Object)
      allow(mock_tag_ase).to receive(:key).and_return('Environment')
      allow(mock_tag_ase).to receive(:value).and_return('DEV')
      mock_tag_branch = double(Object)
      allow(mock_tag_branch).to receive(:key).and_return('Branch')
      allow(mock_tag_branch).to receive(:value).and_return('master')

      allow(mock_tags_response).to receive(:tag_list).and_return(
        [mock_tag_ams, mock_tag_qda, mock_tag_as, mock_tag_ase, mock_tag_branch]
      )
      sections = { ams: 'ams01', qda: 'c031', as: '99', branch: 'master', ase: 'dev', build: '05' }
      expect {
        AwsHelper.rds_validate_or_copy_db_cluster_snapshot(
          snapshot_identifier: "snapshot",
          component_name: "Test-Component",
          sections: sections
        )
      }.to raise_error RuntimeError, /The Cluster Snapshot ID snapshot does not belong to the current Application Service ID/
    end

    it 'fails with - Unable to execute action Snapshot for' do
      allow(Context).to receive_message_chain('kms.secrets_key_arn').and_return('dummy-kms-key')
      allow(AwsHelper).to receive(:rds_describe_cluster_snapshot_attributes).and_raise(RuntimeError)
      sections = { ams: 'ams01', qda: 'c031', as: '99', branch: 'master', ase: 'dev', build: '05' }
      expect {
        AwsHelper.rds_validate_or_copy_db_cluster_snapshot(
          snapshot_identifier: "snapshot",
          component_name: "Test-Component",
          sections: sections
        )
      }.to raise_error /Unable to execute action Snapshot/
    end
  end

  context 'rds_wait_for_snapshot_to_available' do
    it 'raise error if the snapshot not exist' do
      client = double(Aws::RDS::Client)
      db_snapshot_msg = double(Object, :db_snapshots => [], :db_cluster_snapshots => nil)

      allow(@dummy_class).to receive(:_rds_client).and_return(client)
      allow(client).to receive(:describe_db_snapshots).and_return(db_snapshot_msg)

      expect {
        @dummy_class.rds_wait_for_snapshot(snapshot_identifier: "snapshot")
      }.to raise_error(RuntimeError, /RDS Snapshot "snapshot" does not exist/)
    end

    it 'test successfull status' do
      client = double(Aws::RDS::Client)
      db_snapshot_msg = double(Object)
      db_snapshot = double(Aws::RDS::Types::DBSnapshot)
      db_snapshots_array = []
      db_snapshots_array << db_snapshot
      allow(db_snapshot).to receive(:db_snapshot_identifier) .and_return("db_snapshot_1")
      allow(db_snapshot).to receive(:status) .and_return("available")
      allow(db_snapshot).to receive(:percent_progress) .and_return("100")
      allow(@dummy_class).to receive(:_rds_client).and_return(client)
      allow(client).to receive(:describe_db_snapshots).and_return(db_snapshot_msg)
      allow(db_snapshot_msg).to receive(:db_snapshots) .and_return(db_snapshots_array)

      expect(@dummy_class.rds_wait_for_snapshot(snapshot_identifier: "snapshot")).to eq(true)
    end

    it 'test timeout issue' do
      client = double(Aws::RDS::Client)

      db_snapshot_msg = double(Object)
      db_snapshot = double(Aws::RDS::Types::DBSnapshot)
      db_snapshots_array = []
      db_snapshots_array << db_snapshot

      allow(db_snapshot).to receive(:db_snapshot_identifier) .and_return("db_snapshot_1")
      allow(db_snapshot).to receive(:status) .and_return("inprogress")
      allow(db_snapshot).to receive(:percent_progress) .and_return("100")
      allow(@dummy_class).to receive(:_rds_client).and_return(client)
      allow(client).to receive(:describe_db_snapshots).and_return(db_snapshot_msg)
      allow(db_snapshot_msg).to receive(:db_snapshots) .and_return(db_snapshots_array)

      expect {
        @dummy_class.rds_wait_for_snapshot(
          snapshot_identifier: "snapshot",
          max_attempts: 2,
          delay: 0.05
        )
      }      .to raise_error(RuntimeError, /Timed out waiting for RDS Snapshot to available/)
    end
  end

  context 'rds_wait_for_cluster_snapshot_to_available' do
    it 'raise error if the snapshot not exist' do
      client = double(Aws::RDS::Client)
      db_snapshot_msg = double(Object, :db_snapshots => [], :db_cluster_snapshots => nil)
      allow(@dummy_class).to receive(:_rds_client).and_return(client)
      allow(client).to receive(:describe_db_cluster_snapshots).and_return(db_snapshot_msg)
      allow(client).to receive(:db_cluster_snapshots)

      expect {
        @dummy_class.rds_wait_for_cluster_snapshot(snapshot_identifier: "snapshot")
      }.to raise_error(/RDS Cluster Snapshot "snapshot" does not exist/)
    end

    it 'raise error if the snapshot not exist' do
      client = double(Aws::RDS::Client)
      db_cluster_snapshot_msg = double(Object)
      db_cluster_snapshot = double(Aws::RDS::Types::DBClusterSnapshot)
      db_snapshots_array = []
      db_snapshots_array << db_cluster_snapshot
      allow(db_cluster_snapshot).to receive(:db_snapshot_identifier) .and_return("db_snapshot_1")
      allow(db_cluster_snapshot).to receive(:status) .and_return("available")
      allow(db_cluster_snapshot).to receive(:percent_progress) .and_return("100")
      allow(@dummy_class).to receive(:_rds_client).and_return(client)
      allow(client).to receive(:describe_db_cluster_snapshots).and_return(db_cluster_snapshot_msg)
      allow(db_cluster_snapshot_msg).to receive(:db_cluster_snapshots) .and_return(db_snapshots_array)

      expect(@dummy_class.rds_wait_for_cluster_snapshot(snapshot_identifier: "snapshot")).to eq(true)
    end

    it 'test RDS Cluster Snapshot doesnot exist' do
      client = double(Aws::RDS::Client)
      db_cluster_snapshot_msg = double(Object)
      db_cluster_snapshot = double(Aws::RDS::Types::DBClusterSnapshot)
      db_snapshots_array = []
      allow(@dummy_class).to receive(:_rds_client).and_return(client)
      allow(client).to receive(:describe_db_cluster_snapshots).and_return(db_cluster_snapshot_msg)
      allow(db_cluster_snapshot_msg).to receive(:db_cluster_snapshots) .and_return(db_snapshots_array)

      expect {
        @dummy_class.rds_wait_for_cluster_snapshot(
          snapshot_identifier: "snapshot",
        )
      }.to raise_error /RDS Cluster Snapshot "snapshot" does not exist/
    end

    it 'test timeout issue' do
      client = double(Aws::RDS::Client)
      db_cluster_snapshot_msg = double(Object)
      db_cluster_snapshot = double(Aws::RDS::Types::DBClusterSnapshot)
      db_snapshots_array = []
      db_snapshots_array << db_cluster_snapshot
      allow(db_cluster_snapshot).to receive(:db_snapshot_identifier) .and_return("db_snapshot_1")
      allow(db_cluster_snapshot).to receive(:status) .and_return("inprogress")
      allow(db_cluster_snapshot).to receive(:percent_progress) .and_return("100")
      allow(@dummy_class).to receive(:_rds_client).and_return(client)
      allow(client).to receive(:describe_db_cluster_snapshots).and_return(db_cluster_snapshot_msg)
      allow(db_cluster_snapshot_msg).to receive(:db_cluster_snapshots) .and_return(db_snapshots_array)

      expect {
        @dummy_class.rds_wait_for_cluster_snapshot(
          snapshot_identifier: "snapshot",
          max_attempts: 2,
          delay: 0.1
        )
      } .to raise_error(RuntimeError, /Timed out waiting for RDS Snapshot to become available/)
    end
  end

  context 'rds_validate_or_copy_db_instance_snapshot' do
    it 'raise error if the snapshot not exist' do
      allow(Context).to receive_message_chain('kms.secrets_key_arn')
      mock_snapshot_attributes = double(Object)
      allow(@dummy_class).to receive(:rds_describe_snapshot_attributes).and_return(mock_snapshot_attributes)
      allow(mock_snapshot_attributes).to receive(:encrypted).and_return(true)
      allow(mock_snapshot_attributes).to receive(:kms_key_id).and_return('dummy-kms-key')
      allow(@dummy_class).to receive(:rds_copy_db_instance_snapshot)
      allow(@dummy_class).to receive(:rds_wait_for_snapshot)

      expect {
        @dummy_class.rds_validate_or_copy_db_instance_snapshot(
          snapshot_identifier: 'snapshot',
          component_name: 'mysql',
          sections: {}
        )
      }.to raise_error(RuntimeError, /KMS key for application service #{Defaults.kms_secrets_key_alias} is not found./)
    end

    it 'return the same snapshot id if snapshot encrypted and with same cmk key' do
      dummy_client = double(Aws::RDS::Client)
      allow(AwsHelper).to receive(:_rds_client).and_return(dummy_client)

      allow(Context).to receive_message_chain('environment.account_id').and_return('123456789')

      mock_tags_response = double(Object)
      allow(dummy_client).to receive(:list_tags_for_resource).and_return(mock_tags_response)

      mock_tag_ams = double(Object)
      allow(mock_tag_ams).to receive(:key).and_return('AMSID')
      allow(mock_tag_ams).to receive(:value).and_return('AMS01')
      mock_tag_qda = double(Object)
      allow(mock_tag_qda).to receive(:key).and_return('EnterpriseAppID')
      allow(mock_tag_qda).to receive(:value).and_return('C031')
      mock_tag_as = double(Object)
      allow(mock_tag_as).to receive(:key).and_return('ApplicationServiceID')
      allow(mock_tag_as).to receive(:value).and_return('99')
      mock_tag_ase = double(Object)
      allow(mock_tag_ase).to receive(:key).and_return('Environment')
      allow(mock_tag_ase).to receive(:value).and_return('DEV')
      mock_tag_branch = double(Object)
      allow(mock_tag_branch).to receive(:key).and_return('Branch')
      allow(mock_tag_branch).to receive(:value).and_return('master')

      allow(mock_tags_response).to receive(:tag_list).and_return(
        [mock_tag_ams, mock_tag_qda, mock_tag_as, mock_tag_ase, mock_tag_branch]
      )

      allow(Context).to receive_message_chain('kms.secrets_key_arn').and_return('dummy-kms-key')
      describe_snapshot_response = double(Object)
      allow(AwsHelper).to receive(:rds_describe_snapshot_attributes).and_return(describe_snapshot_response)
      allow(describe_snapshot_response).to receive(:encrypted).and_return(true)
      allow(describe_snapshot_response).to receive(:kms_key_id).and_return('dummy-kms-key')
      sections = { ams: 'ams01', qda: 'c031', as: '99', branch: 'master', ase: 'dev', build: '05' }
      expect(
        AwsHelper.rds_validate_or_copy_db_instance_snapshot(
          snapshot_identifier: "snapshot",
          component_name: "Test-Component",
          sections: sections,
          cmk_arn: 'dummy-kms-key'
        )
      ).to eq('snapshot')
    end
    it 'return the copysnapshot id if the snapshot is unecrypted' do
      dummy_client = double(Aws::RDS::Client)
      allow(AwsHelper).to receive(:_rds_client).and_return(dummy_client)

      allow(Context).to receive_message_chain('environment.account_id').and_return('123456789')

      mock_tags_response = double(Object)
      allow(dummy_client).to receive(:list_tags_for_resource).and_return(mock_tags_response)

      mock_tag_ams = double(Object)
      allow(mock_tag_ams).to receive(:key).and_return('AMSID')
      allow(mock_tag_ams).to receive(:value).and_return('AMS01')
      mock_tag_qda = double(Object)
      allow(mock_tag_qda).to receive(:key).and_return('EnterpriseAppID')
      allow(mock_tag_qda).to receive(:value).and_return('C031')
      mock_tag_as = double(Object)
      allow(mock_tag_as).to receive(:key).and_return('ApplicationServiceID')
      allow(mock_tag_as).to receive(:value).and_return('99')
      mock_tag_ase = double(Object)
      allow(mock_tag_ase).to receive(:key).and_return('Environment')
      allow(mock_tag_ase).to receive(:value).and_return('DEV')
      mock_tag_branch = double(Object)
      allow(mock_tag_branch).to receive(:key).and_return('Branch')
      allow(mock_tag_branch).to receive(:value).and_return('master')

      allow(mock_tags_response).to receive(:tag_list).and_return(
        [mock_tag_ams, mock_tag_qda, mock_tag_as, mock_tag_ase, mock_tag_branch]
      )

      allow(Context).to receive_message_chain('kms.secrets_key_arn').and_return('dummy-kms-key')
      describe_snapshot_response = double(Object)
      allow(AwsHelper).to receive(:rds_describe_snapshot_attributes).and_return(describe_snapshot_response)
      allow(describe_snapshot_response).to receive(:encrypted).and_return(false)
      allow(describe_snapshot_response).to receive(:kms_key_id).and_return('dummy-key-id')
      allow(AwsHelper).to receive(:rds_copy_db_instance_snapshot).and_return('dummy-copy-snapshot-id')
      allow(Defaults).to receive(:snapshot_identifier)
      allow(Defaults).to receive(:get_tags)
      allow(AwsHelper).to receive(:rds_wait_for_snapshot)
      sections = { ams: 'ams01', qda: 'c031', as: '99', branch: 'master', ase: 'dev', build: '05' }
      expect(
        AwsHelper.rds_validate_or_copy_db_instance_snapshot(
          snapshot_identifier: "snapshot",
          component_name: "Test-Component",
          sections: sections,
          cmk_arn: 'dummy-kms-key'
        )
      ).to eq('dummy-copy-snapshot-id')
    end

    it 'return the copysnapshot id if the snapshot is encrypted with different key' do
      dummy_client = double(Aws::RDS::Client)
      allow(AwsHelper).to receive(:_rds_client).and_return(dummy_client)

      allow(Context).to receive_message_chain('environment.account_id').and_return('123456789')

      mock_tags_response = double(Object)
      allow(dummy_client).to receive(:list_tags_for_resource).and_return(mock_tags_response)

      mock_tag_ams = double(Object)
      allow(mock_tag_ams).to receive(:key).and_return('AMSID')
      allow(mock_tag_ams).to receive(:value).and_return('AMS01')
      mock_tag_qda = double(Object)
      allow(mock_tag_qda).to receive(:key).and_return('EnterpriseAppID')
      allow(mock_tag_qda).to receive(:value).and_return('C031')
      mock_tag_as = double(Object)
      allow(mock_tag_as).to receive(:key).and_return('ApplicationServiceID')
      allow(mock_tag_as).to receive(:value).and_return('99')
      mock_tag_ase = double(Object)
      allow(mock_tag_ase).to receive(:key).and_return('Environment')
      allow(mock_tag_ase).to receive(:value).and_return('DEV')
      mock_tag_branch = double(Object)
      allow(mock_tag_branch).to receive(:key).and_return('Branch')
      allow(mock_tag_branch).to receive(:value).and_return('master')

      allow(mock_tags_response).to receive(:tag_list).and_return(
        [mock_tag_ams, mock_tag_qda, mock_tag_as, mock_tag_ase, mock_tag_branch]
      )

      allow(Context).to receive_message_chain('kms.secrets_key_arn').and_return('dummy-kms-key')
      describe_snapshot_response = double(Object)
      allow(AwsHelper).to receive(:rds_describe_snapshot_attributes).and_return(describe_snapshot_response)
      allow(describe_snapshot_response).to receive(:encrypted).and_return(true)
      allow(describe_snapshot_response).to receive(:kms_key_id).and_return('other-key-id')
      allow(AwsHelper).to receive(:rds_copy_db_instance_snapshot).and_return('dummy-copy-snapshot-id')
      allow(Defaults).to receive(:snapshot_identifier)
      allow(Defaults).to receive(:get_tags)
      allow(AwsHelper).to receive(:rds_wait_for_snapshot)
      sections = { ams: 'ams01', qda: 'c031', as: '99', branch: 'master', ase: 'dev', build: '05' }
      expect(
        AwsHelper.rds_validate_or_copy_db_instance_snapshot(
          snapshot_identifier: "snapshot",
          component_name: "Test-Component",
          sections: sections,
          cmk_arn: 'dummy-kms-key'
        )
      ).to eq('dummy-copy-snapshot-id')
    end

    it 'failure - incorrect application service id ...' do
      dummy_client = double(Aws::RDS::Client)
      allow(AwsHelper).to receive(:_rds_client).and_return(dummy_client)

      allow(Context).to receive_message_chain('environment.account_id').and_return('123456789')

      mock_tags_response = double(Object)
      allow(dummy_client).to receive(:list_tags_for_resource).and_return(mock_tags_response)

      mock_tag_ams = double(Object)
      allow(mock_tag_ams).to receive(:key).and_return('AMSID')
      allow(mock_tag_ams).to receive(:value).and_return('AMS01')
      mock_tag_qda = double(Object)
      allow(mock_tag_qda).to receive(:key).and_return('EnterpriseAppID')
      allow(mock_tag_qda).to receive(:value).and_return('C036')
      mock_tag_as = double(Object)
      allow(mock_tag_as).to receive(:key).and_return('ApplicationServiceID')
      allow(mock_tag_as).to receive(:value).and_return('99')
      mock_tag_ase = double(Object)
      allow(mock_tag_ase).to receive(:key).and_return('Environment')
      allow(mock_tag_ase).to receive(:value).and_return('DEV')
      mock_tag_branch = double(Object)
      allow(mock_tag_branch).to receive(:key).and_return('Branch')
      allow(mock_tag_branch).to receive(:value).and_return('master')

      allow(mock_tags_response).to receive(:tag_list).and_return(
        [mock_tag_ams, mock_tag_qda, mock_tag_as, mock_tag_ase, mock_tag_branch]
      )

      allow(Context).to receive_message_chain('kms.secrets_key_arn').and_return('dummy-kms-key')
      describe_snapshot_response = double(Object)
      allow(AwsHelper).to receive(:rds_describe_snapshot_attributes).and_return(describe_snapshot_response)
      allow(describe_snapshot_response).to receive(:encrypted).and_return(true)
      allow(describe_snapshot_response).to receive(:kms_key_id).and_return('other-key-id')
      allow(AwsHelper).to receive(:rds_copy_db_instance_snapshot).and_return('dummy-copy-snapshot-id')
      allow(Defaults).to receive(:snapshot_identifier)
      allow(Defaults).to receive(:get_tags)
      allow(AwsHelper).to receive(:rds_wait_for_snapshot)
      sections = { ams: 'ams01', qda: 'c031', as: '99', branch: 'master', ase: 'dev', build: '05' }
      expect {
        AwsHelper.rds_validate_or_copy_db_instance_snapshot(
          snapshot_identifier: "snapshot",
          component_name: "Test-Component",
          sections: sections,
          cmk_arn: 'dummy-kms-key'
        )
      }.to raise_error RuntimeError, /The Snapshot ID snapshot does not belong to the current Application Service ID/
    end
  end

  context 'rds_delete_db_cluster_snapshots' do
    it 'successfully deleted snapshots' do
      dummy_client = double(Aws::RDS::Client)
      allow(AwsHelper).to receive(:_rds_client).and_return(dummy_client)
      allow(dummy_client).to receive(:delete_db_cluster_snapshot)
      expect {
        AwsHelper.rds_delete_db_cluster_snapshots(
          snapshot_ids: ["snapshot"]
        )
      }.not_to raise_error
    end
    it 'test failure' do
      dummy_client = double(Aws::RDS::Client)
      allow(AwsHelper).to receive(:_rds_client).and_return(dummy_client)
      allow(dummy_client).to receive(:delete_db_cluster_snapshot).and_raise(RuntimeError)
      expect {
        AwsHelper.rds_delete_db_cluster_snapshots(
          snapshot_ids: ["snapshot"]
        )
      }.to raise_error(RuntimeError, /Failed to delete snapshot/)
    end
  end

  context 'rds_delete_db_instance_snapshots' do
    it 'successfully deleted snapshots' do
      dummy_client = double(Aws::RDS::Client)
      allow(AwsHelper).to receive(:_rds_client).and_return(dummy_client)
      allow(dummy_client).to receive(:delete_db_snapshot)
      expect {
        AwsHelper.rds_delete_db_instance_snapshots(
          snapshot_ids: ["snapshot"]
        )
      }.not_to raise_error
    end
    it 'test failure' do
      dummy_client = double(Aws::RDS::Client)
      allow(AwsHelper).to receive(:_rds_client).and_return(dummy_client)
      allow(dummy_client).to receive(:delete_db_snapshot).and_raise(RuntimeError)
      expect {
        AwsHelper.rds_delete_db_instance_snapshots(
          snapshot_ids: ["snapshot"]
        )
      }.to raise_error(RuntimeError, /Failed to delete snapshot/)
    end
  end
  context 'rds_reset_password' do
    it 'successfully reset password for db_instance_identifier' do
      dummy_client = double(Aws::RDS::Client)
      allow(AwsHelper).to receive(:_rds_client).and_return(dummy_client)
      allow(dummy_client).to receive(:modify_db_instance)
      expect {
        AwsHelper.rds_reset_password(
          db_instance_identifier: "snapshot",
          password: "anu9djsd9sdj"
        )
      }.not_to raise_error
    end
    it 'successfully reset password for db_cluster_identifier' do
      dummy_client = double(Aws::RDS::Client)
      allow(AwsHelper).to receive(:_rds_client).and_return(dummy_client)
      allow(dummy_client).to receive(:modify_db_cluster)
      expect {
        AwsHelper.rds_reset_password(
          db_cluster_identifier: "snapshot",
          password: "anu9djsd9sdj"
        )
      }.not_to raise_error
    end
    it 'Failure - Test without any snapshot identifier' do
      dummy_client = double(Aws::RDS::Client)
      allow(AwsHelper).to receive(:_rds_client).and_return(dummy_client)
      expect {
        AwsHelper.rds_reset_password(
          password: "anu9djsd9sdj"
        )
      }.to raise_error /Either db_instance_identifier or db_cluster_identifier must be specified./
    end
    it 'Failure - Failed to reset RDS password' do
      dummy_client = double(Aws::RDS::Client)
      allow(AwsHelper).to receive(:_rds_client).and_return(dummy_client)
      allow(dummy_client).to receive(:modify_db_cluster).and_raise(RuntimeError)
      expect {
        AwsHelper.rds_reset_password(
          db_cluster_identifier: "snapshot",
          password: "anu9djsd9sdj"
        )
      }.to raise_error /Failed to reset RDS password/
    end
  end
end
