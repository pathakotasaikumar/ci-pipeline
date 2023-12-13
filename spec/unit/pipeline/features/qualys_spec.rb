$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib"))
require 'pipeline/features/qualys.rb'
require 'util/os'

RSpec.describe Pipeline::Features::Qualys do
  context 'initialize' do
    it 'successfully initialises Qualys feature ' do
      component = double(Consumable)
      expect {
        Pipeline::Features::Qualys.new(
          component, {
            'Enabled' => 'true',
            'Recipients' => ['test@example.com']
          }
        )
      }.not_to raise_error
    end

    it 'fails to initialise Qualys feature ' do
      component = double(Consumable)
      expect {
        Pipeline::Features::Qualys.new(
          component, {
            'Enabled' => 'true'
          }
        )
      }.to raise_exception(KeyError)
    end
  end

  before :context do
    component = double(Consumable)
    @enabled_pipeline_feature_qualys = Pipeline::Features::Qualys.new(
      component, {
        'Enabled' => 'true',
        'Recipients' => ['test@example.com']
      }
    )

    @disabled_pipeline_feature_qualys = Pipeline::Features::Qualys.new(
      component, {
        'Enabled' => 'false',
        'Recipients' => ['test@example.com']
      }
    )
  end

  context 'activate' do
    it 'successfully executes active - enabled' do
      allow(@enabled_pipeline_feature_qualys).to receive(:_generate_scan_payload) .and_return(
        {
          "tags" => { key: 'test', value: 'test' },
          "account_id" => '0123456789012',
          "recipients" => ['test@example.com'],
          "execution_id" => 'dummy-execution-id'
        }
      )
      allow(@enabled_pipeline_feature_qualys).to receive(:_execute_scan) .and_return(true)
      expect { @enabled_pipeline_feature_qualys.activate(:PostDeploy) }.not_to raise_error
    end

    it 'successfully executes active - disabled' do
      expect { @disabled_pipeline_feature_qualys.activate(:PostDeploy) }.not_to raise_error
    end

    it 'failed activate' do
      allow(@enabled_pipeline_feature_qualys).to receive(:_generate_scan_payload).and_raise(StandardError)
      expect(Log).to receive(:error).with(/Failed to execute Qualys scan request/)
      expect { @enabled_pipeline_feature_qualys.activate(:PostDeploy) }.not_to raise_exception
    end

    it 'fails to activate - with wrong stage' do
      allow(@enabled_pipeline_feature_qualys).to receive(:_generate_scan_payload).and_return({})
      expect(Log).to receive(:error).with(/Failed to execute Qualys scan request/)
      expect { @enabled_pipeline_feature_qualys.activate(:PreDeploy) }.not_to raise_exception
    end
  end

  context 'feature_tags' do
    it 'successfully return feature_tags' do
      expect(@enabled_pipeline_feature_qualys.feature_tags).to eq([{ key: 'feature_qualys', value: 'enabled' }])
    end

    it 'successfully return feature_tags' do
      expect(@disabled_pipeline_feature_qualys.feature_tags).to eq([{ key: 'feature_qualys', value: 'disabled' }])
    end
  end

  context 'feature_properties' do
    it 'successfully return feature_properties' do
      expect(@enabled_pipeline_feature_qualys.feature_properties).to eq({ 'status' => 'enabled' })
    end

    it 'successfully return feature_properties - disabled' do
      expect(@disabled_pipeline_feature_qualys.feature_properties).to eq({ 'status' => 'disabled' })
    end
  end

  context '_execute_scan' do
    it 'successfully runs execute_scan' do
      mock_client = double(Object)
      allow(mock_client).to receive(:lambda_invoke)
      allow(@enabled_pipeline_feature_qualys).to receive(:_lambda_client).and_return(mock_client)
      expect { @enabled_pipeline_feature_qualys.send(:_execute_scan, 'dummy-dunction', {}) }.not_to raise_exception
    end

    it 'fails to execute_scan' do
      allow(@enabled_pipeline_feature_qualys).to receive(:_lambda_client) .and_raise(RuntimeError)
      expect { @enabled_pipeline_feature_qualys.send(:_execute_scan, 'dummy-dunction', {}) }.to raise_exception(RuntimeError)
    end
  end

  context '_generate_payload' do
    it 'successfully execute generate_payload' do
      component = double(Consumable)
      feature_qualys = Pipeline::Features::Qualys.new(component, 'Enabled' => 'true', 'Recipients' => ['test@example.com'])
      expect(feature_qualys.send(:_generate_scan_payload)).to be_a(Hash)
    end
  end

  context '_component_tags' do
    it 'successfully execute component_tags' do
      component = double(Consumable)
      feature_qualys = Pipeline::Features::Qualys.new(component, 'Enabled' => 'true', 'Recipients' => ['test@example.com'])
      expect { feature_qualys.send(:_component_tags) }.not_to raise_exception
    end
  end

  context '_lambda_client' do
    it 'successfully return lambda client' do
      component = double(Consumable)
      feature_qualys = Pipeline::Features::Qualys.new(component, 'Enabled' => 'true', 'Recipients' => ['test@example.com'])
      expect { feature_qualys.send(:_lambda_client) }.not_to raise_exception
    end
  end
end
