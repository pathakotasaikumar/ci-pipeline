$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib"))
require 'pipeline/features/customtags.rb'
require 'util/os'

RSpec.describe Pipeline::Features::CustomTags do
  context 'initialize' do
    it 'successfully initialises CustomTags feature ' do
      component = double(Consumable)
      expect {
        Pipeline::Features::CustomTags.new(
          component, { 'Enabled' => 'true' }
        )
      }.not_to raise_error
    end
  end

  before :context do
    component = double(Consumable)
    @enabled_pipeline_feature_customtags = Pipeline::Features::CustomTags.new(
      component, {
        'Enabled' => 'true'
      }
    )

    @disabled_pipeline_feature_customtags = Pipeline::Features::CustomTags.new(
      component, {
        'Enabled' => 'false'
      }
    )
  end

  context 'feature_properties' do
    it 'successfully return feature_properties' do
      expect(@enabled_pipeline_feature_customtags.feature_properties).to eq({ 'status' => 'enabled' })
    end

    it 'successfully return feature_properties - disabled' do
      expect(@disabled_pipeline_feature_customtags.feature_properties).to eq({ 'status' => 'disabled' })
    end
  end

  context '_component_tags' do
    it 'successfully execute component_tags' do
      component = double(Consumable)
      feature_customtags = Pipeline::Features::CustomTags.new(component, 'Enabled' => 'true', 'Tags' => ['MyTag'])
      expect { feature_customtags.send(:_component_tags) }.not_to raise_exception
    end
  end
end
