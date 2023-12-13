$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws/builders")
require 'db_instance_snapshot_builder'
require 'json'

describe 'DbInstanceSnapshotBuilder' do
  before(:context) do
    @dummy_class = DummyClass.new
    @dummy_class.extend(DbInstanceSnapshotBuilder)
    @kms_key_id = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
  end

  context '_process_db_instance_snapshot' do
    it 'success returns latest instance snapshot' do
      allow(Context).to receive_message_chain('environment.variable').and_return(nil)
      allow(Context).to receive_message_chain('persist.released_build_number').and_return('2')
      allow(Context).to receive_message_chain('component.variable').and_return('dummy_arn')
      allow(Context).to receive_message_chain('component.set_variables')

      allow(@dummy_class).to receive(:_latest_db_instance_snapshot).and_return('latest-validated-instance-snapshot')
      expect(
        @dummy_class._process_db_instance_snapshot(
          snapshot_id: '@latest',
          component_name: 'mysql',
          resource_name: 'MyDatabase'
        )
      ).to eq("latest-validated-instance-snapshot")
    end

    it 'success takes instance snapshot' do
      allow(Context).to receive_message_chain('environment.variable').and_return(nil)
      allow(Context).to receive_message_chain('persist.released_build_number').and_return('2')
      allow(Context).to receive_message_chain('component.variable').and_return('dummy_arn')
      allow(Context).to receive_message_chain('component.set_variables')

      allow(@dummy_class).to receive(:_take_db_instance_snapshot).and_return('latest-validated-instance-snapshot')
      expect(
        @dummy_class._process_db_instance_snapshot(
          snapshot_id: 'take-snapshot',
          component_name: 'mysql',
          resource_name: 'MyDatabase'
        )
      ).to eq("latest-validated-instance-snapshot")
    end

    it 'success validates real instance snapshot' do
      allow(Context).to receive_message_chain('environment.variable').and_return(true)
      allow(Context).to receive_message_chain('persist.released_build_number').and_return('2')
      allow(Context).to receive_message_chain('component.variable').and_return('dummy_arn')
      allow(Context).to receive_message_chain('component.set_variables')
      allow(AwsHelper).to receive(:rds_validate_or_copy_db_instance_snapshot).and_return('encrypted-latest-validated-instance-snapshot')
      allow(@dummy_class).to receive(:_take_db_instance_snapshot).and_return('latest-validated-instance-snapshot')
      allow(@dummy_class).to receive(:default_instance_section_variable)
      expect(
        @dummy_class._process_db_instance_snapshot(
          snapshot_id: 'dummy-snapshot-id',
          component_name: 'mysql',
          resource_name: 'MyDatabase'
        )
      ).to eq('encrypted-latest-validated-instance-snapshot')
    end

    it 'fails with - WARNING: No valid RDS instance' do
      allow(Context).to receive_message_chain('environment.variable').and_return(nil)
      allow(Context).to receive_message_chain('persist.released_build_number').and_return('2')
      allow(Context).to receive_message_chain('component.variable').and_return('dummy_arn')
      allow(@dummy_class).to receive(:_validate_db_instance_snapshot).and_return(nil)
      expect {
        @dummy_class._process_db_instance_snapshot(
          snapshot_id: 'dummy-snapshot-id',
          component_name: 'aurora',
          resource_name: 'MyDatabase'
        )
      }      .to raise_exception /WARNING: No valid RDS Instance /
    end

    it 'fails quietly on debug' do
      allow(Context).to receive_message_chain('environment.variable').and_return(true)
      allow(Context).to receive_message_chain('persist.released_build_number').and_return('2')
      allow(Context).to receive_message_chain('component.variable').and_return('dummy_arn')
      allow(@dummy_class).to receive(:_validate_db_instance_snapshot).and_return(nil)
      expect {
        @dummy_class._process_db_instance_snapshot(
          snapshot_id: 'dummy-snapshot-id',
          component_name: 'aurora',
          resource_name: 'MyDatabase'
        )
      }      .not_to raise_exception
    end
  end

  context '_latest_db_instance_snapshot' do
    it 'success' do
      allow(AwsHelper).to receive(:rds_instance_latest_snapshot).and_return('latest-validated-instance-snapshot')
      allow(AwsHelper).to receive(:rds_validate_or_copy_db_instance_snapshot).and_return('latest-validated-instance-snapshot')
      allow(@dummy_class).to receive(:default_instance_section_variable)
      expect(
        @dummy_class._latest_db_instance_snapshot(
          component_name: 'aurora',
          db_instance: 'dummy-instance'
        )
      ).to eq('latest-validated-instance-snapshot')
    end

    it 'success, add to temp snapshots' do
      allow(AwsHelper).to receive(:rds_instance_latest_snapshot).and_return('latest-instance-snapshot')
      allow(AwsHelper).to receive(:rds_validate_or_copy_db_instance_snapshot).and_return('latest-validated-instance-snapshot')
      allow(Context).to receive_message_chain('component.variable').and_return([])
      allow(Context).to receive_message_chain('component.set_variables')
      allow(@dummy_class).to receive(:default_instance_section_variable)
      expect(
        @dummy_class._latest_db_instance_snapshot(
          component_name: 'aurora',
          db_instance: 'dummy-instance'
        )
      ).to eq('latest-validated-instance-snapshot')
    end

    it 'success - skip on nil argument' do
      expect {
        @dummy_class._latest_db_instance_snapshot(
          component_name: nil,
          db_instance: nil
        )
      }.not_to raise_exception
    end
  end

  context '_take_db_instance_snapshot' do
    it 'success' do
      allow(AwsHelper).to receive(:rds_instance_create_snapshot).and_return('instance-snapshot')
      allow(AwsHelper).to receive(:rds_wait_for_snapshot)
      allow(AwsHelper).to receive(:rds_validate_or_copy_db_instance_snapshot).and_return('validated-instance-snapshot')
      allow(AwsHelper).to receive(:rds_delete_db_instance_snapshots)
      allow(@dummy_class).to receive(:default_instance_section_variable)
      expect(
        @dummy_class._take_db_instance_snapshot(
          component_name: 'aurora',
          db_instance: 'dummy-instance'
        )
      ).to eq('validated-instance-snapshot')
    end

    it 'success - skip on nil argument' do
      expect {
        @dummy_class._take_db_instance_snapshot(
          component_name: nil,
          db_instance: nil
        )
      }.not_to raise_exception
    end

    it 'fails with FAIL: Failed to execute snapshot on' do
      expect {
        allow(AwsHelper).to receive(:rds_instance_create_snapshot).and_raise StandardError
        @dummy_class._take_db_instance_snapshot(
          component_name: 'aurora',
          db_instance: 'dummy-instance'
        )
      }.to raise_exception StandardError
    end
  end
  context '_process_target_db_instance_snapshot' do
    it 'success returns latest instance snapshot' do
      allow(Context).to receive_message_chain('environment.variable').and_return(nil)
      allow(Context).to receive_message_chain('component.variables').and_return('dummy_arn')

      allow(@dummy_class).to receive(:_latest_db_instance_snapshot).and_return('latest-validated-instance-snapshot')
      expect(
        @dummy_class._process_target_db_instance_snapshot(
          snapshot_tags: {
            "ASE" => "dev",
            "BuildNumber" => "2",
            "Branch" => "master",
            "ComponentName" => "mysql",
            "ResourceName" => "MyDatabase"
          }
        )
      ).to eq("latest-validated-instance-snapshot")
    end
    it 'fails with - WARNING: No valid RDS instance' do
      allow(Context).to receive_message_chain('environment.variable').and_return(nil)
      allow(Context).to receive_message_chain('persist.released_build_number').and_return('2')
      allow(Context).to receive_message_chain('component.variables').and_return('dummy_arn')
      allow(@dummy_class).to receive(:_latest_db_instance_snapshot).and_return(nil)
      expect {
        @dummy_class._process_target_db_instance_snapshot(
          snapshot_tags: {
            "ASE" => "dev",
            "BuildNumber" => "2",
            "Branch" => "master",
            "ComponentName" => "mysql",
            "ResourceName" => "MyDatabase"
          }
        )
      } .to raise_exception /WARNING: No valid Snapshot was identified /
    end

    it 'does not raise error on non-debug' do
      service = @dummy_class.clone

      allow(Context).to receive_message_chain('environment.variable')
        .with('allow_missing_snapshot_target', false)
        .and_return('true')

      allow(service).to receive(:_latest_db_instance_snapshot).and_return(nil)

      expect {
        result = service.__send__(:_process_target_db_instance_snapshot, snapshot_tags: { build: nil })
      }.to_not raise_error
    end

    it 'raises error on debug' do
      service = @dummy_class.clone

      allow(Context).to receive_message_chain('environment.variable')
        .with('allow_missing_snapshot_target', false)
        .and_return('false')

      allow(service).to receive(:_latest_db_instance_snapshot).and_return(nil)

      expect {
        result = service.__send__(:_process_target_db_instance_snapshot, snapshot_tags: { build: nil })
      }.to raise_error(/No valid Snapshot was identified from RDS Instance/)
    end

    it 'composes db_instance_arn for build' do
      allow(Context).to receive_message_chain('component.variables')
        .and_return({
          :component => 's',
          'my-component.my-resourceArn' => 'my-arn'
        })
      allow(Context).to receive_message_chain('environment.variable')
        .with('allow_missing_snapshot_target', false)
        .and_return('false')

      allow(@dummy_class).to receive(:_latest_db_instance_snapshot).and_return('my-snapshot')

      result = nil

      expect {
        result = @dummy_class.__send__(
          :_process_target_db_instance_snapshot,
          snapshot_tags: {
            build: 'build-1',
            ase: 'ase-1',
            branch: 'branch-1',
            component: 'my-component',
            resource: 'my-resource'
          }
        )
      }.to_not raise_error

      expect(result).to eq('my-snapshot')
    end
  end

  context '.default_section_variable' do
    it 'returns value' do
      sections = Defaults.sections
      result = @dummy_class.send(:default_instance_section_variable)

      expect(result.count).to be(6)
      expect(result.class).to be(Hash)

      expect(sections[:ams]).to be(sections[:ams])
      expect(sections[:qda]).to be(sections[:qda])
      expect(sections[:as]).to be(sections[:as])
      expect(sections[:ase]).to be(sections[:ase])
      expect(sections[:branch]).to be(sections[:branch])
      expect(sections[:build]).to be(sections[:build])
    end
  end
end
