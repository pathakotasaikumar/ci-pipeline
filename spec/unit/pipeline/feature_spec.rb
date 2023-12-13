$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib"))
require 'pipeline/feature.rb'

RSpec.describe Pipeline::Feature do
  context 'initialize' do
    it 'successfully initialises Qualys feature ' do
      component = double(Consumable)
      expect {
        Pipeline::Feature.new(component, { 'Enabled' => 'true' })
      }.not_to raise_error
    end

    it 'fails to initialise - missing Enabled property ' do
      component = double(Consumable)
      expect {
        Pipeline::Feature.new(component, { 'unknown' => 'true' })
      }.to raise_exception(KeyError)
    end
  end

  before :context do
    @component = double(Consumable)
  end

  context 'enabled?' do
    it 'feature is enabled with true' do
      feature = Pipeline::Feature.new(@component, { 'Enabled' => 'true' })
      expect(feature.enabled?).to eq(true)
    end

    it 'feature is enabled with True' do
      feature = Pipeline::Feature.new(@component, { 'Enabled' => 'True' })
      expect(feature.enabled?).to eq(true)
    end

    it 'feature is enabled with :true' do
      feature = Pipeline::Feature.new(@component, { 'Enabled' => :true })
      expect(feature.enabled?).to eq(true)
    end

    it 'feature is disabled with false' do
      feature = Pipeline::Feature.new(@component, { 'Enabled' => 'false' })
      expect(feature.enabled?).to eq(false)
    end

    it 'feature is disabled with nil' do
      feature = Pipeline::Feature.new(@component, { 'Enabled' => nil })
      expect(feature.enabled?).to eq(false)
    end
  end

  context 'instantiate' do
    it 'success - instantiate Qualys' do
      expect {
        Pipeline::Feature.instantiate(@component, 'qualys', { 'Enabled' => 'true', 'Recipients' => 'test@example.com' })
      }.not_to raise_exception
    end

    it 'success - instantiate Datadog' do
      expect {
        Pipeline::Feature.instantiate(@component, 'datadog', { 'Enabled' => 'false' })
      }.not_to raise_exception
    end

    it 'success - instantiate CodeDeploy' do
      expect {
        Pipeline::Feature.instantiate(@component, 'codedeploy', { 'Enabled' => 'false' })
      }.not_to raise_exception
    end

    it 'fails to instantiate an Unknown feature with /Unknown Feature/' do
      expect { Pipeline::Feature.instantiate(@component, 'unknown', {}) }.to raise_exception(/Unknown feature "unknown"/)
    end
  end
end
