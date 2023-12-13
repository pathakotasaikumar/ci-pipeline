$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib/consumables/aws/"))
require 'consumables/aws/actions/register_api'
require 'consumables/aws/actions/http_request'
require 'consumables/aws/aws_instance'
require 'consumable'

RSpec.describe RegisterApi do
  before do
    @args = {
      params: {
        'Basepath' => 'qcp-pipeline-dev',
        'Swagger' => { this: 'that' },
        'ApiConf' => { this: 'that' },
        'Target' => '@deployed'
      },
      stage: "PreRelease",
      step: "01"
    }

    Context.environment.set_variables(
      'api_gateway_admin_url_nonp' => 'http://dummy',
      'api_gateway_username' => 'dummy',
      'api_gateway_password' => 'dummy'
    )
  end

  it 'valid_stages' do
    instance = double Consumable
    allow(instance).to receive(:type).and_return('aws/instance')

    Log.debug Defaults.api_gateway_admin_url
    expect {
      kwargs = { component: instance }.merge @args
      @action = RegisterApi.new(**kwargs)
    }.not_to raise_exception

    expect { @action.valid_stages }.not_to raise_exception
    expect(@action.valid_stages).to be_a Array
  end

  it 'valid_components' do
    instance = double Consumable
    allow(instance).to receive(:type).and_return('aws/instance')
    expect {
      kwargs = { component: instance }.merge(@args)
      @action = RegisterApi.new(**kwargs)
    }.not_to raise_exception

    expect { @action.valid_stages }.not_to raise_exception
    expect(@action.valid_stages).to be_a Array
  end

  it 'run_at valid stage' do
    instance = double Consumable
    allow(instance).to receive(:type).and_return('aws/instance')
    expect {
      kwargs = { component: instance }.merge @args
      @action = RegisterApi.new(**kwargs)
    }.not_to raise_exception

    expect(@action.run_at? 'PostRelease').to eq(true)
    expect(@action.run_at? 'PreRelease').to eq(true)
    expect(@action.run_at? 'PostRelease').to eq(true)
  end

  it 'run_by valid component' do
    instance = double Consumable
    allow(instance).to receive(:type).and_return('aws/instance')
    expect {
      kwargs = { component: instance }.merge @args
      @action = RegisterApi.new(**kwargs)
    }.not_to raise_exception

    expect(@action.run_by? 'aws/instance').to eq(true)
    expect(@action.run_by? 'aws/autoscale').to eq(true)
    expect(@action.run_by? 'aws/autoheal').to eq(true)
  end

  context 'invoke' do
    it 'invoke' do
      instance = double Consumable
      allow(instance).to receive(:type).and_return('aws/instance')
      expect {
        kwargs = { component: instance }.merge @args
        @action = RegisterApi.new(**kwargs)
      }.not_to raise_exception

      # RegisterApi.invoke calls super, so mocking at first parent class
      allow_any_instance_of(HTTPRequest).to receive(:invoke)
      @action.invoke
    end

    it 'invoke aws/lambda register api - success' do
      lambda = double Consumable
      allow(lambda).to receive(:type).and_return('aws/lambda')
      allow(lambda).to receive(:component_name).and_return('my-lambda')
      allow(AwsHelper).to receive(:lambda_get_policy).and_return({})
      allow(AwsHelper).to receive(:lambda_add_permission)
      allow(Context).to receive_message_chain('component.variable').and_return('my-test-function-arn')

      expect(Log).to receive(:info).with(/Successfully added invoke permission on my-lambda and target my-test-function-arn/)
      expect {
        kwargs = { component: lambda }.merge @args
        @action = RegisterApi.new(**kwargs)
      }.not_to raise_exception

      # RegisterApi.invoke calls super, so mocking at first parent class
      allow_any_instance_of(HTTPRequest).to receive(:invoke)
      @action.invoke
    end

    it 'invoke aws/lambda register api - failure' do
      lambda = double Consumable
      allow(lambda).to receive(:type).and_return('aws/lambda')
      allow(lambda).to receive(:component_name).and_return('my-lambda')
      allow(AwsHelper).to receive(:lambda_get_policy).and_return({})
      allow(AwsHelper).to receive(:lambda_add_permission).and_raise(StandardError)
      allow(Context).to receive_message_chain('component.variable').and_return('my-test-function-arn')

      kwargs = { component: lambda }.merge @args
      @action = RegisterApi.new(**kwargs)

      # RegisterApi.invoke calls super, so mocking at first parent class
      allow_any_instance_of(HTTPRequest).to receive(:invoke)
      expect { @action.invoke }.to raise_exception /Failed to add invoke permission to the function/
    end

    it 'invoke aws/lambda register api - failure' do
      lambda = double Consumable
      allow(lambda).to receive(:type).and_return('aws/lambda')
      allow(lambda).to receive(:component_name).and_return('my-lambda')
      allow(AwsHelper).to receive(:lambda_get_policy).and_return({})
      allow(AwsHelper).to receive(:lambda_add_permission).and_raise(StandardError)
      allow(Context).to receive_message_chain('component.variable').and_return('my-test-function-arn')

      kwargs = { component: lambda }.merge @args
      @action = RegisterApi.new(**kwargs)

      # RegisterApi.invoke calls super, so mocking at first parent class
      allow_any_instance_of(HTTPRequest).to receive(:invoke)
      expect { @action.invoke }.to raise_exception /Failed to add invoke permission to the function/
    end

    it 'invoke aws/lambda register api - failure but continue the action with @stop_on_error = false' do
      lambda = double Consumable
      allow(lambda).to receive(:type).and_return('aws/lambda')
      allow(lambda).to receive(:component_name).and_return('my-lambda')
      allow(AwsHelper).to receive(:lambda_get_policy).and_return({})
      allow(AwsHelper).to receive(:lambda_add_permission).and_raise(StandardError)
      allow(Context).to receive_message_chain('component.variable').and_return('my-test-function-arn')

      expect(Log).to receive(:warn).with(/Failed to add invoke permission to the function @released -StandardError. Skipping SetRegisterApi action/)
      args = {
        params: {
          'Basepath' => 'qcp-pipeline-dev',
          'Swagger' => { this: 'that' },
          'ApiConf' => { this: 'that' },
          'StopOnError' => false
        },
        stage: "PreRelease",
        step: "01"
      }

      kwargs = { component: lambda }.merge args
      @action = RegisterApi.new(**kwargs)

      # RegisterApi.invoke calls super, so mocking at first parent class
      allow_any_instance_of(HTTPRequest).to receive(:invoke)
      expect { @action.invoke }.not_to raise_exception
    end

    it 'invoke aws/lambda register api - validation policy statement as false' do
      lambda = double Consumable
      dummy_object = double(Object)
      allow(lambda).to receive(:type).and_return('aws/lambda')
      allow(lambda).to receive(:component_name).and_return('my-lambda')

      allow(Context).to receive_message_chain('component.variable').and_return('my-test-function-arn')

      kwargs = { component: lambda }.merge @args
      @action = RegisterApi.new(**kwargs)

      allow(@action).to receive(:_validate_lambda_policy_statement).and_return(false)
      # RegisterApi.invoke calls super, so mocking at first parent class
      allow_any_instance_of(HTTPRequest).to receive(:invoke)
      allow(AwsHelper).to receive(:lambda_get_policy).and_return(dummy_object)
      allow(AwsHelper).to receive(:lambda_add_permission)
      expect { @action.invoke }.not_to raise_exception
    end

    it 'invoke aws/lambda register api - validating policy statement as true' do
      lambda = double Consumable
      dummy_object = double(Object)
      allow(lambda).to receive(:type).and_return('aws/lambda')
      allow(lambda).to receive(:component_name).and_return('my-lambda')
      allow(AwsHelper).to receive(:lambda_get_policy).and_return(dummy_object)
      allow(AwsHelper).to receive(:lambda_add_permission)
      allow(Context).to receive_message_chain('component.variable').and_return('my-test-function-arn')

      kwargs = { component: lambda }.merge @args
      @action = RegisterApi.new(**kwargs)

      allow(@action).to receive(:_validate_lambda_policy_statement).and_return(true)
      # RegisterApi.invoke calls super, so mocking at first parent class
      allow_any_instance_of(HTTPRequest).to receive(:invoke)

      expect { @action.invoke }.not_to raise_exception
    end
  end

  context '_validate_lambda_policy_statement' do
    it 'return true after validating' do
      lambda = double Consumable

      allow(lambda).to receive(:type).and_return('aws/lambda')
      allow(lambda).to receive(:component_name).and_return('my-lambda')
      kwargs = { component: lambda }.merge @args
      @action = RegisterApi.new(**kwargs)

      policy_statement = { "Version" => "2012-10-17", "Statement" => [{ "Sid" => "test", "Effect" => "Allow" }, { "Sid" => "event", "Effect" => "Allow" }] }
      expect(@action.send(:_validate_lambda_policy_statement, policy_statement: policy_statement, sid_to_validate: 'test')).to eq(true)
    end

    it 'return false after validating' do
      lambda = double Consumable

      allow(lambda).to receive(:type).and_return('aws/lambda')
      allow(lambda).to receive(:component_name).and_return('my-lambda')
      kwargs = { component: lambda }.merge @args
      @action = RegisterApi.new(**kwargs)

      policy_statement = { "Version" => "2012-10-17", "Statement" => [{ "Sid" => "event", "Effect" => "Allow" }] }
      expect(@action.send(:_validate_lambda_policy_statement, policy_statement: policy_statement, sid_to_validate: 'test')).to eq(false)
    end
  end
end # RSpec.describe
