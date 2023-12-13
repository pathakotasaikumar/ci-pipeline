$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib/consumables/aws/"))
require 'consumables/aws/actions/snapshot'
require 'consumables/aws/aws_instance'
require 'consumable'

RSpec.describe Snapshot do
  before do
    @args = {
      stage: "PostDeploy",
      step: "01"
    }
  end

  def _get_action_instance(params: nil, component_type: 'aws/volume')
    instance = double Consumable

    allow(instance).to receive(:type).and_return(component_type)
    allow(instance).to receive(:component_name).and_return('my-component')

    allow(instance).to receive(:volume).and_return({
      'my-volume' => 'value'
    })

    allow(instance).to receive(:db_instances).and_return({
      'my-db' => 'value'
    })

    allow(instance).to receive(:db_cluster).and_return({
      'my-cluster' => 'value'
    })

    final_params = { component: instance }.merge(@args)
    if (params != nil)
      final_params = final_params.merge(params)
    end

    Snapshot.new(**final_params)
  end

  def _get_valid_action_instance(params = nil, component_type: 'aws/volume')
    allow(Context).to receive_message_chain('environment.variable')
      .with('shared_accounts', [])
      .and_return(['123456789012'])

    _get_action_instance(params: params, component_type: component_type)
  end

  context '.initialize' do
    it 'creates an instance' do
      expect {
        action = _get_valid_action_instance
      }.not_to raise_error
    end

    it 'does not accept parameters' do
      expect {
        _get_action_instance(params: {
          :params => { 'my' => 1 }
        })
      }.to raise_error(/Action Snapshot does not accept parameters/)
    end
  end

  context '.valid_stages' do
    it 'returns value' do
      action = _get_valid_action_instance

      expect { action.valid_stages }.not_to raise_exception
      expect(action.valid_stages).to eq(
        %w(
          PostDeploy
          PreRelease
          PostRelease
          PreTeardown
        )
      )
      expect(action.valid_stages).to be_a Array
    end
  end

  context '.valid_components' do
    it 'valid_components' do
      action = _get_valid_action_instance

      expect { action.valid_components }.not_to raise_exception
      expect(action.valid_components).to eq(
        %w(
          aws/volume
          aws/rds-mysql
          aws/rds-postgresql
          aws/rds-sqlserver
          aws/rds-oracle
          aws/rds-aurora
          aws/rds-aurora-postgresql
        )
      )
      expect(action.valid_components).to be_a Array
    end
  end

  context '.invoke' do
    it 'raises on unknown component' do
      fake_component = double(Object)

      allow(fake_component).to receive(:type).and_return('aws/unknown')
      allow(fake_component).to receive(:component_name).and_return('unknown_component')

      action = _get_valid_action_instance(
        component_type: 'aws/volume'
      )

      action.instance_variable_set(:@component, fake_component)

      expect {
        action.invoke
      }.to raise_error(/Unable to action Snapshot for component/)
    end

    it 'raises on failed snapshot' do
      action = _get_valid_action_instance(
        component_type: 'aws/volume'
      )

      snapshot_id = 'new-aws/volume-snapshot-id'

      expect(action).to receive(:snapshot_volume).and_raise('cannot perform snapshot')

      allow(Context).to receive_message_chain('component.variable')
        .with('my-component', 'TempSnapshots', [])
        .and_return([])

      allow(Context).to receive_message_chain('component.set_variables')

      expect {
        action.invoke
      }.to raise_error(/cannot perform snapshot/)
    end

    it 'backs up aws/volume' do
      action = _get_valid_action_instance(
        component_type: 'aws/volume'
      )

      snapshot_id = 'new-aws/volume-snapshot-id'

      expect(action).to receive(:snapshot_volume).and_return(snapshot_id)

      allow(Context).to receive_message_chain('component.variable')
        .with('my-component', 'TempSnapshots', [])
        .and_return([])

      allow(Context).to receive_message_chain('component.set_variables')

      expect {
        action.invoke
      }.not_to raise_error
    end

    it 'backs up aws/rds cmponents' do
      component_types = [
        'aws/rds-mysql', 'aws/rds-oracle', 'aws/rds-postgresql', 'aws/rds-sqlserver'
      ]

      component_types.each do |component_type|
        action = _get_valid_action_instance(
          component_type: component_type
        )

        snapshot_id = 'new-aws/volume-snapshot-id'

        expect(action).to receive(:snapshot_rds_instance).and_return(snapshot_id)

        allow(Context).to receive_message_chain('component.variable')
          .with('my-component', 'TempSnapshots', [])
          .and_return([])

        allow(Context).to receive_message_chain('component.set_variables')

        expect {
          action.invoke
        }.not_to raise_error
      end
    end

    it 'backs up aws/rds cmponents' do
      component_types = [
        'aws/rds-aurora'
      ]

      component_types.each do |component_type|
        action = _get_valid_action_instance(
          component_type: component_type
        )

        snapshot_id = 'new-aws/volume-snapshot-id'

        expect(action).to receive(:snapshot_rds_cluster).and_return(snapshot_id)

        allow(Context).to receive_message_chain('component.variable')
          .with('my-component', 'TempSnapshots', [])
          .and_return([])

        allow(Context).to receive_message_chain('component.set_variables')

        expect {
          action.invoke
        }.not_to raise_error
      end
    end
  end

  context '.snapshot_volume' do
    it 'creates snapshot' do
      action = _get_valid_action_instance(
        component_type: 'aws/volume'
      )

      allow(AwsHelper).to receive(:ec2_create_volume_snapshot)
      allow(Context).to receive_message_chain('component.variable')

      allow(Defaults).to receive(:snapshot_identifier)
      allow(Defaults).to receive(:get_tags)

      expect {
        action.send(:snapshot_volume)
      }.not_to raise_error
    end
  end

  context '.snapshot_rds_instance' do
    it 'creates snapshot' do
      action = _get_valid_action_instance(
        component_type: 'aws/rds-mysql'
      )

      allow(AwsHelper).to receive(:rds_instance_create_snapshot)
      allow(Context).to receive_message_chain('component.variable')
        .with('my-component', anything, nil)
        .and_return('my-db-value')

      allow(Defaults).to receive(:snapshot_identifier)
      allow(Defaults).to receive(:get_tags)

      expect {
        action.send(:snapshot_rds_instance)
      }.not_to raise_error
    end
  end

  context '.snapshot_rds_cluster' do
    it 'creates snapshot' do
      action = _get_valid_action_instance(
        component_type: 'aws/rds-aurora'
      )

      allow(AwsHelper).to receive(:rds_cluster_create_snapshot)
      allow(Context).to receive_message_chain('component.variable')
        .with('my-component', anything, nil)
        .and_return('my-db-cluster')

      allow(Defaults).to receive(:snapshot_identifier)
      allow(Defaults).to receive(:get_tags)

      expect {
        action.send(:snapshot_rds_cluster)
      }.not_to raise_error
    end
  end
end # RSpec.describe
