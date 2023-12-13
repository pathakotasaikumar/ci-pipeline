$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib/consumables/aws/"))
require 'consumables/aws/actions/add_launch_permission'
require 'consumables/aws/aws_instance'
require 'consumable'

RSpec.describe AddLaunchPermission do
  before do
    @args = {
      stage: "PostRelease",
      step: "01"
    }
  end

  def _get_action_instance
    instance = double Consumable

    allow(instance).to receive(:type).and_return('aws/image')
    allow(instance).to receive(:bake_instance_name).and_return('aws/image')
    allow(instance).to receive(:component_name).and_return('my-component')

    kwargs = { component: instance }.merge(@args)
    AddLaunchPermission.new(**kwargs)
  end

  def _get_valid_action_instance
    allow(Context).to receive_message_chain('environment.variable')
      .with('shared_accounts', [])
      .and_return(['123456789012'])

    _get_action_instance
  end

  context '.initialize' do
    it 'creates an instance' do
      expect {
        action = _get_valid_action_instance
      }.not_to raise_error
    end

    it 'requires shared_accounts variable' do
      expect {
        action = _get_action_instance
      }.to raise_error(/AddLaunchPermission action requires shared_account/)
    end
  end

  context '.valid_stages' do
    it 'returns value' do
      action = _get_valid_action_instance

      expect { action.valid_stages }.not_to raise_exception
      expect(action.valid_stages).to eq([
                                          "PostDeploy",
                                          "PreRelease",
                                          "PostRelease",
                                        ])
      expect(action.valid_stages).to be_a Array
    end
  end

  context '.valid_components' do
    it 'valid_components' do
      action = _get_valid_action_instance

      expect { action.valid_components }.not_to raise_exception
      expect(action.valid_components).to eq([
                                              "aws/image"
                                            ])
      expect(action.valid_components).to be_a Array
    end
  end

  context '.invoke' do
    it 'fails on ImageId = nil' do
      action = _get_valid_action_instance
      allow(Context).to receive_message_chain('component.variable')
        .with('my-component', 'ImageId', nil)
        .and_return(nil)

      expect { action.invoke }.to raise_error(ActionError)
    end

    it 'runs on ImageId != nil' do
      action = _get_valid_action_instance
      allow(Context).to receive_message_chain('component.variable')
        .with('my-component', 'ImageId', nil)
        .and_return('ami-42')

      allow(AwsHelper).to receive(:ec2_add_launch_permission)
      expect { action.invoke }.not_to raise_error
    end

    it 'fails on launch_permission error' do
      action = _get_valid_action_instance
      allow(Context).to receive_message_chain('component.variable')
        .with('my-component', 'ImageId', nil)
        .and_return('ami-42')

      allow(AwsHelper).to receive(:ec2_add_launch_permission)
        .and_raise('cannot run AWS provision')

      expect { action.invoke }.to raise_error(/Failed to execute AddLaunchPermission/)
    end
  end
end # RSpec.describe
