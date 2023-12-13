$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib/consumables/aws/"))
require 'consumables/aws/actions/invoke_lambda'
require 'consumable'

RSpec.describe InvokeLambda do
  before do
    @args = {
      params: {
        'LambdaFunction' => 'Function',
        'Target' => '@deployed',
        'Payload' => {
          'var1' => '1',
          'var2' => '2'
        }
      },
      stage: "PreRelease",
      step: "01"
    }
  end

  context 'initialize' do
    it 'successfully initialises ' do
      instance = double Consumable
      allow(instance).to receive(:type).and_return('aws/lambda')
      expect {
        kwargs = { component: instance }.merge @args
        @invoke_lambda = InvokeLambda.new(**kwargs)
      }.not_to raise_exception
    end
  end

  context 'invoke' do
    it 'successfully executes' do
      args = {
        params: {
          'LambdaFunction' => 'Function',
          'Target' => '@deployed',
          'Payload' => {
            'var1' => '1',
            'var2' => '2'
          }
        },
        stage: "PreRelease",
        step: "01"
      }
      instance = double Consumable
      allow(instance).to receive(:type).and_return('aws/lambda')
      allow(instance).to receive(:component_name).and_return('instance')
      allow(Context).to receive_message_chain('component.variable').and_return('dummy-arn')
      allow(Context).to receive_message_chain('component.replace_variables')
      mock_response = double(Object)
      allow(AwsHelper).to receive(:lambda_invoke).and_return(mock_response)
      allow(mock_response).to receive(:log_result)
      allow(mock_response).to receive(:function_error)
      expect(mock_response.function_error).to be(nil)
      expect {
        kwargs = { component: instance }.merge args
        @invoke_lambda = InvokeLambda.new(**kwargs)
      }.not_to raise_exception
      expect { @invoke_lambda.invoke }.not_to raise_exception
    end

    it 'fails on lambda execution' do
      args = {
        params: {
          'LambdaFunction' => 'Function',
          'Target' => '@deployed',
          'FailOnException' => 'true',
          'Payload' => {
            'var1' => '1',
            'var2' => '2'
          }
        },
        stage: "PreRelease",
        step: "01"
      }
      instance = double Consumable
      allow(instance).to receive(:type).and_return('aws/lambda')
      allow(instance).to receive(:component_name).and_return('instance')
      allow(Context).to receive_message_chain('component.variable').and_return('dummy-arn')
      allow(Context).to receive_message_chain('component.replace_variables')
      mock_response = double(Object)
      allow(AwsHelper).to receive(:lambda_invoke).and_return(mock_response)
      allow(mock_response).to receive(:log_result)
      allow(mock_response).to receive(:function_error).and_return('Handled', 'Unhandled')
      expect(mock_response.function_error).not_to be(nil)

      expect {
        kwargs = { component: instance }.merge args
        @invoke_lambda = InvokeLambda.new(**kwargs)
      }.not_to raise_exception
      expect { @invoke_lambda.invoke }.to raise_exception /Failed to execute 'instance' action InvokeLambda - Failed lambda function execution/
    end

    it 'successfully executes - released' do
      args = {
        params: {
          'LambdaFunction' => 'Function',
          'Target' => '@released',
          'Payload' => {
            'var1' => '1',
            'var2' => '2'
          }
        },
        stage: "PreRelease",
        step: "01"
      }
      instance = double Consumable
      allow(instance).to receive(:type).and_return('aws/lambda')
      allow(instance).to receive(:component_name).and_return('instance')
      allow(Context).to receive_message_chain('component.variable').and_return('dummy-arn')
      allow(Context).to receive_message_chain('component.replace_variables')
      mock_response = double(Object)
      allow(AwsHelper).to receive(:lambda_invoke).and_return(mock_response)
      allow(mock_response).to receive(:log_result)
      allow(mock_response).to receive(:function_error)
      expect(mock_response.function_error).to be(nil)
      expect {
        kwargs = { component: instance }.merge args
        @invoke_lambda = InvokeLambda.new(**kwargs)
      }.not_to raise_exception
      expect { @invoke_lambda.invoke }.not_to raise_exception
    end

    it 'fails on lambda execution - released' do
      args = {
        params: {
          'LambdaFunction' => 'Function',
          'Target' => '@released',
          'FailOnException' => 'true',
          'Payload' => {
            'var1' => '1',
            'var2' => '2'
          }
        },
        stage: "PreRelease",
        step: "01"
      }
      instance = double Consumable
      allow(instance).to receive(:type).and_return('aws/lambda')
      allow(instance).to receive(:component_name).and_return('instance')
      allow(Context).to receive_message_chain('component.variable').and_return('dummy-arn')
      allow(Context).to receive_message_chain('component.replace_variables')
      mock_response = double(Object)
      allow(AwsHelper).to receive(:lambda_invoke).and_return(mock_response)
      allow(mock_response).to receive(:log_result)
      allow(mock_response).to receive(:function_error).and_return('Handled', 'Unhandled')
      expect(mock_response.function_error).not_to be(nil)

      expect {
        kwargs = { component: instance }.merge args
        @invoke_lambda = InvokeLambda.new(**kwargs)
      }.not_to raise_exception
      expect { @invoke_lambda.invoke }.to raise_exception /Failed to execute 'instance' action InvokeLambda - Failed lambda function execution/
    end

    it 'fails with - Failed to execute instance action InvokeLambda' do
      args = {
        params: {
          'LambdaFunction' => 'Function',
          'Target' => '@released',
          'Payload' => {
            'var1' => '1',
            'var2' => '2'
          }
        },
        stage: "PreRelease",
        step: "01"
      }
      instance = double Consumable
      allow(instance).to receive(:type).and_return('aws/lambda')
      allow(instance).to receive(:component_name).and_return('instance')
      allow(Context).to receive_message_chain('component.variable').and_return('dummy-arn')
      allow(Context).to receive_message_chain('component.replace_variables')
      allow(AwsHelper).to receive(:lambda_invoke).and_raise StandardError

      expect {
        kwargs = { component: instance }.merge args
        @invoke_lambda = InvokeLambda.new(**kwargs)
      }.not_to raise_exception
      expect { @invoke_lambda.invoke }.to raise_exception /Failed to execute 'instance' action InvokeLambda - StandardError/
    end
  end
end
