$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib/consumables/aws/"))
require 'consumables/aws/actions/qualys_was'
require 'consumable'

RSpec.describe QualysWAS do
  before do
    @args = {
      params: {
        'ScanConf' => {
          'qualys_was' => 'dummy'
        }
      },
      stage: "PostDeploy",
      step: "01",
    }
  end

  it 'valid_stages' do
    instance = double Consumable
    allow(instance).to receive(:type).and_return('aws/instance')

    expect {
      kwargs = { component: instance }.merge @args
      @action = QualysWAS.new(**kwargs)
    }.not_to raise_exception

    expect { @action.valid_stages }.not_to raise_exception
    expect(@action.valid_stages).to be_a Array
  end

  it 'valid_components' do
    instance = double Consumable
    allow(instance).to receive(:type).and_return('aws/instance')
    expect {
      kwargs = { component: instance }.merge(@args)
      @action = QualysWAS.new(**kwargs)
    }.not_to raise_exception

    expect { @action.valid_stages }.not_to raise_exception
    expect(@action.valid_stages).to be_a Array
  end

  it 'run_at valid stage' do
    instance = double Consumable
    allow(instance).to receive(:type).and_return('aws/instance')
    expect {
      kwargs = { component: instance }.merge @args
      @action = QualysWAS.new(**kwargs)
    }.not_to raise_exception

    expect(@action.run_at? 'PostRelease').to eq(true)
    expect(@action.run_at? 'PostDeploy').to eq(true)
    expect(@action.run_at? 'PreRelease').to eq(false)
  end

  it 'run_by valid component' do
    instance = double Consumable
    allow(instance).to receive(:type).and_return('aws/instance')
    expect {
      kwargs = { component: instance }.merge @args
      @action = QualysWAS.new(**kwargs)
    }.not_to raise_exception

    expect(@action.run_by? 'aws/instance').to eq(true)
    expect(@action.run_by? 'aws/autoscale').to eq(true)
    expect(@action.run_by? 'aws/autoheal').to eq(true)
  end

  context '_execute_scan' do
    it 'successfully runs execute_scan' do
      mock_client = double(Object)
      allow(mock_client).to receive(:lambda_invoke)
      instance = double Consumable
      allow(instance).to receive(:type).and_return('aws/instance')
      expect {
        kwargs = { component: instance }.merge @args
        @action = QualysWAS.new(**kwargs)
      }.not_to raise_exception

      allow(@action).to receive(:_aws_helper_client).and_return(mock_client)
      expect { @action.send(:_execute_scan, 'dummy-dunction', {}) }.not_to raise_exception
    end

    it 'fails to execute_scan' do
      instance = double Consumable
      allow(instance).to receive(:type).and_return('aws/instance')
      expect {
        kwargs = { component: instance }.merge @args
        @action = QualysWAS.new(**kwargs)
      }.not_to raise_exception
      allow(@action).to receive(:_aws_helper_client) .and_raise(RuntimeError)
      expect { @action.send(:_execute_scan, 'dummy-dunction', {}) }.to raise_exception(RuntimeError)
    end
  end

  context '_generate_was_scan_payload' do
    it 'successfully execute generate_was_scan_payload' do
      instance = double Consumable
      allow(instance).to receive(:type).and_return('aws/instance')
      expect {
        kwargs = { component: instance }.merge @args
        @action = QualysWAS.new(**kwargs)
      }.not_to raise_exception
      expect(@action.send(:_generate_was_scan_payload)).to be_a(Hash)
    end
  end

  context '_component_tags' do
    it 'successfully execute component_tags' do
      instance = double(Consumable)
      allow(instance).to receive(:type).and_return('aws/instance')
      expect {
        kwargs = { component: instance }.merge @args
        @action = QualysWAS.new(**kwargs)
      }.not_to raise_exception
      expect { @action.send(:_component_tags) }.not_to raise_exception
    end
  end

  context '_aws_helper_client' do
    it 'successfully return _aws_helper_client' do
      instance = double(Consumable)
      allow(instance).to receive(:type).and_return('aws/instance')
      expect {
        kwargs = { component: instance }.merge @args
        @action = QualysWAS.new(**kwargs)
      }.not_to raise_exception
      expect { @action.send(:_aws_helper_client) }.not_to raise_exception
    end
  end

  context 'invoke' do
    it 'successfully executes invoke' do
      instance = double(Consumable)
      allow(instance).to receive(:type).and_return('aws/instance')
      expect {
        kwargs = { component: instance }.merge @args
        @action = QualysWAS.new(**kwargs)
      }.not_to raise_exception
      allow(@action).to receive(:_generate_was_scan_payload) .and_return(
        {
          "tags" => { key: 'test', value: 'test' },
          "account_id" => '0123456789012',
          "recipients" => ['test@example.com'],
          "execution_id" => 'dummy-execution-id',
          "qualys_was" => { key: 'test', value: 'test' },
        }
      )
      allow(@action).to receive(:_execute_scan) .and_return(true)
      expect { @action.invoke }.not_to raise_error
    end

    it 'failed to execute invoke - warning' do
      instance = double(Consumable)
      allow(instance).to receive(:type).and_return('aws/instance')
      expect {
        kwargs = { component: instance }.merge @args
        @action = QualysWAS.new(**kwargs)
      }.not_to raise_exception
      allow(@action).to receive(:_generate_was_scan_payload).and_raise(StandardError)
      expect(Log).to receive(:warn).with(/Failed to execute Qualys WAS scan request - StandardError. Skipping Qualys WAS action/)
      expect { @action.invoke }.not_to raise_exception
    end

    it 'failed to execute invoke - raise exception' do
      instance = double(Consumable)
      allow(instance).to receive(:type).and_return('aws/instance')
      @params = {
        params: {
          'ScanConf' => {
            'qualys_was' => 'dummy'
          },
          'StopOnError' => 'true'
        },
        stage: "PostDeploy",
        step: "01",
      }
      expect {
        kwargs = { component: instance }.merge @params
        @action = QualysWAS.new(**kwargs)
      }.not_to raise_exception
      allow(@action).to receive(:_generate_was_scan_payload).and_raise(StandardError)
      expect { @action.invoke }.to raise_exception
    end
  end
end
