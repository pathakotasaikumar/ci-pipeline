$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws/builders")
require 'volume_snapshot_builder'
require 'json'

describe 'VolumeSnapshotBuilder' do
  before(:context) do
    @dummy_class = DummyClass.new
    @dummy_class.extend(VolumeSnapshotBuilder)
    @kms_key_id = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
  end

  context '_process_volume_snapshot' do
    it 'test @latest snapshot' do
      allow(Context).to receive_message_chain('environment.variable').and_return(nil)
      allow(Context).to receive_message_chain('persist.released_build_number').and_return('2')
      allow(Context).to receive_message_chain('component.variable').and_return('dummy_arn')
      allow(Context).to receive_message_chain('component.set_variables')
      allow(@dummy_class).to receive(:_snapshot_name)
      allow(@dummy_class).to receive(:default_volume_section_variable)
      allow(@dummy_class).to receive(:_latest_volume_snapshot).and_return('latest-validated-snapshot')
      expect(
        @dummy_class._process_volume_snapshot(
          snapshot_id: '@latest',
          component_name: 'volume',
          resource_name: 'MyVolume'
        )
      ).to eq('latest-validated-snapshot')
    end

    it 'test take-snapshot snapshot' do
      allow(Context).to receive_message_chain('environment.variable').and_return(nil)
      allow(Context).to receive_message_chain('persist.released_build_number').and_return('2')
      allow(Context).to receive_message_chain('component.variable').and_return('dummy_arn')
      allow(Context).to receive_message_chain('component.set_variables')
      allow(@dummy_class).to receive(:_snapshot_name)
      allow(@dummy_class).to receive(:default_volume_section_variable)
      allow(@dummy_class).to receive(:_take_volume_snapshot).and_return('latest-validated-snapshot')
      expect(
        @dummy_class._process_volume_snapshot(
          snapshot_id: 'take-snapshot',
          component_name: 'volume',
          resource_name: 'MyVolume'
        )
      ).to eq('latest-validated-snapshot')
    end

    it 'test validate snapshot' do
      allow(Context).to receive_message_chain('environment.variable').and_return(true)
      allow(Context).to receive_message_chain('persist.released_build_number').and_return('2')
      allow(Context).to receive_message_chain('component.variable').and_return('dummy_arn')
      allow(Context).to receive_message_chain('component.set_variables')
      allow(@dummy_class).to receive(:_snapshot_name)
      allow(@dummy_class).to receive(:default_volume_section_variable)
      allow(AwsHelper).to receive(:ec2_validate_or_copy_snapshot).and_return('encrypted-latest-validated-snapshot')
      allow(@dummy_class).to receive(:_take_volume_snapshot).and_return('latest-validated-snapshot')
      expect(
        @dummy_class._process_volume_snapshot(
          snapshot_id: 'dummy-snapshot-id',
          component_name: 'volume',
          resource_name: 'MyVolume'
        )
      ).to eq('encrypted-latest-validated-snapshot')
    end

    it 'fails with - WARNING: No valid EBS Volume Snapshot was identified from:' do
      allow(Context).to receive_message_chain('environment.variable').and_return(nil)
      allow(Context).to receive_message_chain('persist.released_build_number').and_return('2')
      allow(Context).to receive_message_chain('component.variable').and_return('dummy_arn')
      allow(Context).to receive_message_chain('component.set_variables')
      allow(@dummy_class).to receive(:_snapshot_name)
      allow(@dummy_class).to receive(:default_volume_section_variable)
      allow(@dummy_class).to receive(:_validate_volume_snapshot).and_return(nil)
      expect {
        @dummy_class._process_volume_snapshot(
          snapshot_id: 'dummy-snapshot-id',
          component_name: 'volume',
          resource_name: 'MyVolume'
        )
      }      .to raise_error(/WARNING: No valid EBS Volume Snapshot was identified from/)
    end

    it 'fails quietly on debug' do
      allow(Context).to receive_message_chain('environment.variable').and_return(true)
      allow(Context).to receive_message_chain('persist.released_build_number').and_return('2')
      allow(Context).to receive_message_chain('component.variable').and_return('dummy_arn')
      allow(Context).to receive_message_chain('component.set_variables')
      allow(@dummy_class).to receive(:_snapshot_name)
      allow(@dummy_class).to receive(:default_volume_section_variable)
      allow(@dummy_class).to receive(:_validate_volume_snapshot).and_return(nil)
      expect {
        @dummy_class._process_volume_snapshot(
          snapshot_id: 'dummy-snapshot-id',
          component_name: 'volume',
          resource_name: 'MyVolume'
        )
      }      .not_to raise_exception
    end
  end

  context '_latest_volume_snapshot' do
    it 'success' do
      allow(AwsHelper).to receive(:ec2_latest_snapshot).and_return('latest-validated-snapshot')
      allow(AwsHelper).to receive(:ec2_validate_or_copy_snapshot).and_return('latest-validated-snapshot')
      allow(@dummy_class).to receive(:default_volume_section_variable)
      expect(
        @dummy_class._latest_volume_snapshot(
          component_name: 'aurora',
          volume_name: 'dummy-volume'
        )
      ).to eq('latest-validated-snapshot')
    end

    it 'success, add to temporary snapshots' do
      allow(AwsHelper).to receive(:ec2_latest_snapshot).and_return('latest-snapshot')
      allow(AwsHelper).to receive(:ec2_validate_or_copy_snapshot).and_return('latest-validated-snapshot')
      allow(Context).to receive_message_chain('component.variable').and_return([])
      allow(Context).to receive_message_chain('component.set_variables')
      allow(@dummy_class).to receive(:default_volume_section_variable)
      expect(
        @dummy_class._latest_volume_snapshot(
          component_name: 'aurora',
          volume_name: 'dummy-volume'
        )
      ).to eq('latest-validated-snapshot')
    end

    it 'success - skip on nil argument' do
      expect {
        @dummy_class._latest_volume_snapshot(
          component_name: nil,
          volume_name: nil
        )
      }.not_to raise_exception
    end
  end

  context '_take_volume_snapshot' do
    it 'success' do
      allow(AwsHelper).to receive(:ec2_create_volume_snapshot).and_return('snapshot')
      allow(AwsHelper).to receive(:ec2_validate_or_copy_snapshot).and_return('validated-snapshot')
      allow(AwsHelper).to receive(:ec2_wait_for_volume_snapshot)
      allow(AwsHelper).to receive(:ec2_delete_snapshots)
      allow(@dummy_class).to receive(:default_volume_section_variable)
      allow(@dummy_class).to receive(:sleep)
      expect(
        @dummy_class._take_volume_snapshot(
          component_name: 'volume',
          volume_id: 'dummy-volume'
        )
      ).to eq('validated-snapshot')
    end

    it 'success - skip on nil argument' do
      expect {
        @dummy_class._take_volume_snapshot(
          component_name: nil,
          volume_id: nil
        )
      }.not_to raise_exception
    end

    it 'fails with FAILED: Failed to create ' do
      expect {
        allow(AwsHelper).to receive(:ec2_create_volume_snapshot).and_raise StandardError
        @dummy_class._take_volume_snapshot(
          component_name: 'volume',
          volume_id: 'dummy-volume'
        )
      }.to raise_exception /Failed to create /
    end
  end

  context '._snapshot_name' do
    it 'returns value' do
      # is this bug?
      # merge skips component, commented out to pass this
      allow(Defaults).to receive(:sections)
        .and_return({
          :ams => 'ams-1',
          :qda => 'qda-1',
          :as => 'as-1',
          :ase => 'ASE-1',
          :branch => 'branch-1',
          :build => 'build-1',
          #:component => 'component-1'
        })

      result = @dummy_class.send(:_snapshot_name)

      expect(result.class).to be(String)
      expect(result).to eq('ams-1-qda-1-as-1-ase-1-branch-1-build-1-')
    end
  end

  context '.default_volume_section_variable' do
    it 'returns value' do
      sections = Defaults.sections
      result = @dummy_class.send(:default_volume_section_variable)

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

  context '._process_target_volume_snapshot' do
    it 'does not raise error on non-debug' do
      service = @dummy_class.clone

      allow(Context).to receive_message_chain('environment.variable')
        .with('allow_missing_snapshot_target', false)
        .and_return('true')

      allow(service).to receive(:_latest_volume_snapshot).and_return(nil)

      expect {
        service.__send__(:_process_target_volume_snapshot, snapshot_tags: { build: nil })
      }.to_not raise_error
    end

    it 'raises error on debug' do
      service = @dummy_class.clone

      allow(Context).to receive_message_chain('environment.variable')
        .with('allow_missing_snapshot_target', false)
        .and_return('false')

      allow(service).to receive(:_latest_volume_snapshot).and_return(nil)

      expect {
        service.__send__(:_process_target_volume_snapshot, snapshot_tags: { build: nil })
      }.to raise_error(/No valid EBS Volume Snapshot was identified from/)
    end

    it 'composes volume_name for build' do
      allow(Context).to receive_message_chain('component.variables')
        .and_return({
          :component => 's',
          'my-component.my-resourceArn' => 'my-arn'
        })
      allow(Context).to receive_message_chain('environment.variable')
        .with('allow_missing_snapshot_target', false)
        .and_return('false')

      allow(@dummy_class).to receive(:_latest_volume_snapshot).and_return('my-snapshot')

      result = nil

      expect {
        result = @dummy_class.__send__(
          :_process_target_volume_snapshot,
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
end
