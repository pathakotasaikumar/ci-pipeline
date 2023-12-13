$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib"))
require 'pipeline/features/ips.rb'
require 'util/os'

RSpec.describe Pipeline::Features::IPS do
  context 'initialize' do
    it 'successfully initialises IPS feature ' do
      component = double(Consumable)
      expect {
        Pipeline::Features::IPS.new(
          component, {
            'Enabled' => 'true',
            'Behaviour' => 'detective'
          }
        )
      }.not_to raise_error
    end

    it 'fails to initialise IPS feature ' do
      component = double(Consumable)
      expect {
        Pipeline::Features::IPS.new(
          component, {
            'Enabld' => 'true'
          }
        )
      }.to raise_exception(KeyError)
    end
  end

  before :context do
    component = double(Consumable)
    @enabled_pipeline_feature_ips = Pipeline::Features::IPS.new(
      component, {
        'Enabled' => 'true',
        'Behaviour' => 'detective'
      }
    )

    @disabled_pipeline_feature_ips = Pipeline::Features::IPS.new(
      component, {
        'Enabled' => 'false'
      }
    )
  end

  context 'activate' do
    it 'successfully executes active - enabled' do
      allow(@enabled_pipeline_feature_ips).to receive(:_generate_atora_payload).and_return(
        {
          "action" => "pre-deploy",
          "tags" => { key: 'test', value: 'test' },
          "account_id" => '0123456789012',
          "behaviour" => 'detective',
          "execution_id" => 'dummy-execution-id'
        }
      )
      allow(@enabled_pipeline_feature_ips).to receive(:_execute_workflow) .and_return(true)
      expect { @enabled_pipeline_feature_ips.activate(:PreDeploy) }.not_to raise_error
    end

    it 'successfully executes activate - disabled' do
      expect(Log).to receive(:info).with('IPS Feature is disabled. Skipping workflow')
      expect { @disabled_pipeline_feature_ips.activate(:PreDeploy) }.not_to raise_error
    end

    it 'failed activate' do
      allow(@enabled_pipeline_feature_ips).to receive(:_generate_atora_payload).and_raise(StandardError)
      expect(Log).to receive(:error).with(/Failed to execute IPS PreDeploy workflow/)
      expect { @enabled_pipeline_feature_ips.activate(:PreDeploy) }.not_to raise_exception
    end

    it 'failes to activate - with wrong stage' do
      allow(@enabled_pipeline_feature_ips).to receive(:_generate_atora_payload).and_return({})
      expect(Log).to receive(:error).with(/Failed to execute IPS PreRelease workflow/)
      expect { @enabled_pipeline_feature_ips.activate(:PreRelease) }.not_to raise_exception
    end
  end

  context 'feature_tags' do
    it 'successfully return feature_tags' do
      expect(@enabled_pipeline_feature_ips.feature_tags).to eq([{ key: 'feature_ips', value: 'detective' }])
    end

    it 'successfully return feature_tags' do
      expect(@disabled_pipeline_feature_ips.feature_tags).to eq([{ key: 'feature_ips', value: 'disabled' }])
    end
  end

  context 'feature_properties' do
    it 'successfully return feature_properties' do
      expect(@enabled_pipeline_feature_ips.feature_properties).to eq({ 'status' => 'enabled' })
    end

    it 'successfully return feature_properties - disabled' do
      expect(@disabled_pipeline_feature_ips.feature_properties).to eq({ 'status' => 'disabled' })
    end
  end

  context '_execute_workflow' do
    it 'successfully runs execute_workflow' do
      mock_client = double(Object)
      allow(mock_client).to receive(:lambda_invoke)
      allow(@enabled_pipeline_feature_ips).to receive(:_lambda_client).and_return(mock_client)
      expect { @enabled_pipeline_feature_ips.send(:_execute_workflow, 'dummy-dunction', {}) }.not_to raise_exception
    end

    it 'fails to execute_workflow' do
      allow(@enabled_pipeline_feature_ips).to receive(:_lambda_client) .and_raise(RuntimeError)
      expect { @enabled_pipeline_feature_ips.send(:_execute_workflow, 'dummy-dunction', {}) }.to raise_exception(RuntimeError)
    end
  end

  context '_generate_payload' do
    it 'successfully execute generate_payload' do
      component = double(Consumable)
      feature_ips = Pipeline::Features::IPS.new(component, 'Enabled' => 'true')
      expect(feature_ips.send(:_generate_atora_payload, :PreDeploy)).to be_a(Hash)
    end
  end

  context '_component_tags' do
    it 'successfully execute component_tags' do
      component = double(Consumable)
      feature_ips = Pipeline::Features::IPS.new(component, 'Enabled' => 'true')
      expect { feature_ips.send(:_component_tags) }.not_to raise_exception
    end
  end

  context '_lambda_client' do
    it 'successfully return lambda client' do
      component = double(Consumable)
      feature_ips = Pipeline::Features::IPS.new(component, 'Enabled' => 'true')
      expect { feature_ips.send(:_lambda_client) }.not_to raise_exception
    end
  end
end
