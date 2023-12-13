$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib"))
require 'pipeline/features/codedeploy.rb'
require 'util/os'

RSpec.describe Pipeline::Features::CodeDeploy do
  context 'initialize' do
    it 'successfully initialises CodeDeploy feature ' do
      component = double(Consumable)
      expect {
        Pipeline::Features::CodeDeploy.new(
          component, { 'Enabled' => 'true' }
        )
      }.not_to raise_error
    end

    it 'successfully initialises CodeDeploy feature - disabled ' do
      component = double(Consumable)
      expect {
        Pipeline::Features::CodeDeploy.new(
          component, { 'Enabled' => 'false' }
        )
      }.not_to raise_error
    end
  end

  before :context do
    component = double(Consumable)
    @enabled_pipeline_feature_codedeploy = Pipeline::Features::CodeDeploy.new(component, { 'Enabled' => 'true' })
    @disabled_pipeline_feature_codedeploy = Pipeline::Features::CodeDeploy.new(component, { 'Enabled' => 'false' })
  end

  context 'feature_tags' do
    it 'successfully return feature_tags' do
      expect(@enabled_pipeline_feature_codedeploy.feature_tags).to eq([{ key: 'feature_codedeploy', value: 'enabled' }])
    end

    it 'successfully return feature_tags - disabled' do
      expect(@disabled_pipeline_feature_codedeploy.feature_tags).to eq([{ key: 'feature_codedeploy', value: 'disabled' }])
    end
  end

  context 'feature_properties' do
    it 'successfully return feature_properties' do
      expect(@enabled_pipeline_feature_codedeploy.feature_properties).to eq({ 'status' => 'enabled' })
    end

    it 'successfully return feature_properties - disabled' do
      expect(@disabled_pipeline_feature_codedeploy.feature_properties).to eq({ 'status' => 'disabled' })
    end
  end
end
