$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib"))
require 'pipeline/features/datadog.rb'
require 'util/os'

RSpec.describe Pipeline::Features::Datadog do
  context 'initialize' do
    it 'successfully initialises Datadog feature ' do
      component = double(Consumable)
      expect {
        Pipeline::Features::Datadog.new(
          component, { 'Enabled' => 'true' }
        )
      }.not_to raise_error
    end

    it 'successfully initialises Datadog feature - disabled ' do
      component = double(Consumable)
      expect {
        Pipeline::Features::Datadog.new(
          component, { 'Enabled' => 'false' }
        )
      }.not_to raise_error
    end
  end

  before :context do
    component = double(Consumable)
    @enabled_pipeline_feature_datadog = Pipeline::Features::Datadog.new(component, { 'Enabled' => 'true' })
    @disabled_pipeline_feature_datadog = Pipeline::Features::Datadog.new(component, { 'Enabled' => 'false' })
  end

  context 'feature_tags' do
    it 'successfully return feature_tags' do
      expect(@enabled_pipeline_feature_datadog.feature_tags).to eq([{ key: 'feature_datadog', value: 'enabled' }])
    end

    it 'successfully return feature_tags - disabled' do
      expect(@disabled_pipeline_feature_datadog.feature_tags).to eq([{ key: 'feature_datadog', value: 'disabled' }])
    end
  end

  context 'feature_properties' do
    it 'successfully return feature_properties' do
      allow(@enabled_pipeline_feature_datadog).to receive(:_api_key) .and_return('dummy-api-key')
      expect(@enabled_pipeline_feature_datadog.feature_properties).to eq({ 'status' => 'enabled', 'apikey' => 'dummy-api-key' })
    end

    it 'successfully return feature_properties - disabled' do
      allow(@disabled_pipeline_feature_datadog).to receive(:_api_key) .and_return('dummy-api-key')
      expect(@disabled_pipeline_feature_datadog.feature_properties).to eq({ 'status' => 'disabled' })
    end
  end

  context '_api_key' do
    it 'successfully return api_key' do
      allow(Defaults).to receive(:sections).and_return(ams: "AMS01", qda: "C031", as: "01", env: "nonp")
      allow(Defaults).to receive(:datadog_api_keys).and_return({ "ams01-nonp" => "dummy-api-key" }.to_json)
      expect(@enabled_pipeline_feature_datadog.send(:_api_key)).to eq('dummy-api-key')
    end
  end
end
