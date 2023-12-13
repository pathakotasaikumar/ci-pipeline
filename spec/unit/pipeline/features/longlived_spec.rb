$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib"))
require 'pipeline/features/longlived.rb'
require 'util/os'

RSpec.describe Pipeline::Features::Longlived do
  context 'initialize' do
    it 'successfully initialises LongLived feature ' do
      component = double(Consumable)
      expect {
        Pipeline::Features::Longlived.new(
          component, {
            'Enabled' => 'true',
            'PuppetServer' => 'dummy-puppet-server',
            'PuppetEnvironment' => 'dummy-environment',
            'PatchGroup' => 'dummy-patch-group'
          }
        )
      }.not_to raise_error
    end

    it 'successfully initialises LongLived feature with RestoreAMI ' do
      component = double(Consumable)
      expect {
        Pipeline::Features::Longlived.new(
          component, {
            'Enabled' => 'true',
            'PuppetServer' => 'dummy-puppet-server',
            'PuppetEnvironment' => 'dummy-environment',
            'PatchGroup' => 'dummy-patch-group',
            'RestoreAMI' => 'ami-0d0806edc9e333cc4'
          }
        )
      }.not_to raise_error
    end

    it 'fails to initialise Longlived feature ' do
      component = double(Consumable)
      expect {
        Pipeline::Features::Longlived.new(
          component, { 'Enabld' => 'true' }
        )
      }.to raise_exception(KeyError)
    end
  end

  before :context do
    component = double(Consumable)
    @enabled_pipeline_feature = Pipeline::Features::Longlived.new(
      component, {
        'Enabled' => 'true',
        'PuppetServer' => 'dummy-puppet-server',
        'PuppetEnvironment' => 'dummy-puppet-environment',
        'PuppetDevelopment' => false,
        'PatchGroup' => 'dummy-patch-group'
      }
    )

    @enabled_pipeline_feature_with_restore = Pipeline::Features::Longlived.new(
      component, {
        'Enabled' => 'true',
        'PuppetServer' => 'dummy-puppet-server',
        'PuppetEnvironment' => 'dummy-puppet-environment',
        'PuppetDevelopment' => false,
        'PatchGroup' => 'dummy-patch-group',
        'RestoreAMI' => 'ami-0d0806edc9e333cc4'
      }
    )

    @enabled_pipeline_feature_default = Pipeline::Features::Longlived.new(
      component, {
        'Enabled' => 'true'
      }
    )

    @disabled_pipeline_feature = Pipeline::Features::Longlived.new(
      component, {
        'Enabled' => 'false',
        'PuppetServer' => 'dummy-puppet-server',
        'PuppetEnvironment' => 'dummy-puppet-environment',
        'PuppetDevelopment' => false,
        'PatchGroup' => 'dummy-patch-group'
      }
    )
  end

  context 'feature_tags' do
    it 'successfully return feature_tags' do
      expect(@enabled_pipeline_feature.feature_tags)
        .to eq([
                 { key: 'feature_longlived', value: 'enabled' },
                 { key: 'Patch Group', value: 'dummy-patch-group' }
               ])
    end

    it 'successfully return feature_tags' do
      expect(@disabled_pipeline_feature.feature_tags)
        .to eq([
                 { key: 'feature_longlived', value: 'disabled' }
               ])
    end
  end

  context 'puppet_environment' do
    it 'successfully returns puppet_environment' do
      expect(@enabled_pipeline_feature.puppet_environment).to eq('dummy-puppet-environment')
    end

    it 'successfully returns default nonp puppet_environment' do
      allow(Defaults).to receive(:sections).and_return(env: 'nonp')
      expect(@enabled_pipeline_feature_default.puppet_environment).to eq('qcp_lri_nonproduction')
    end

    it 'successfully returns default nonp puppet_environment' do
      allow(Defaults).to receive(:sections).and_return(env: 'prod')
      expect(@enabled_pipeline_feature_default.puppet_environment).to eq('qcp_lri_production')
    end
  end

  context 'puppet_server' do
    it 'successfully returns custom puppet_server value' do
      expect(@enabled_pipeline_feature.puppet_server).to eq('dummy-puppet-server')
    end

    it 'successfully returns default puppet_server value' do
      expect(@enabled_pipeline_feature_default.puppet_server).to eq(nil)
    end
  end

  context 'feature_properties' do
    it 'successfully return feature_properties' do
      expect(@enabled_pipeline_feature.feature_properties)
        .to eq({
          'status' => 'enabled',
          'PuppetServer' => 'dummy-puppet-server',
          'PuppetEnvironment' => 'dummy-puppet-environment',
          'PuppetDevelopment' => false,
          'PatchGroup' => 'dummy-patch-group',
          'RestoreAMI' => nil
        })
    end

    it 'successfully return feature_properties - disabled' do
      expect(@disabled_pipeline_feature.feature_properties).to eq({ 'status' => 'disabled' })
    end
  end

  context 'patch_group' do
    it 'successfully runs _patch_group to return windows' do
      allow(Context).to receive_message_chain('component.variable').and_return('windows')
      expect(@enabled_pipeline_feature_default.patch_group).to eq('windows-core-baseline')
    end

    it 'successfully runs _patch_group to return centos' do
      allow(Context).to receive_message_chain('component.variable').and_return('centos')
      expect(@enabled_pipeline_feature_default.patch_group).to eq('centos-core-baseline')
    end

    it 'successfully runs _patch_group to return rhel' do
      allow(Context).to receive_message_chain('component.variable').and_return('rhel')
      expect(@enabled_pipeline_feature_default.patch_group).to eq('rhel-core-baseline')
    end

    it 'successfully runs _patch_group to return custom patch baseline' do
      expect(@enabled_pipeline_feature.patch_group).to eq('dummy-patch-group')
    end

    it 'successfully runs _patch_group to return custom patch baseline' do
      allow(Context).to receive_message_chain('component.variable').and_return('unknown')
      expect { @enabled_pipeline_feature_default.patch_group }.to raise_exception(/Unable to determine Patch Group for operating system/)
    end
  end

  context 'restore ami' do
    it 'successfully returns RestoreAMI property' do
      expect(@enabled_pipeline_feature_with_restore.restore_ami).to eq('ami-0d0806edc9e333cc4')
    end

    it 'successfully return nil for default RestoreAMI property' do
      expect(@enabled_pipeline_feature.restore_ami).to eq(nil)
    end
  end
end
