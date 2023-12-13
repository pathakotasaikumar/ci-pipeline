$LOAD_PATH.unshift("#{BASE_DIR}/lib/aws_helpers")
require 'lambda_helper'

describe 'LambdaHelper' do
  context 'lambda_client' do
    it 'initialize without error' do
      allow(Aws::Lambda::Client).to receive(:new)
      allow(AwsHelper).to receive(:_provisioning_credentials)
      allow(AwsHelper).to receive(:_control_credentials)
      expect { AwsHelper._lambda_client }.not_to raise_exception
    end
  end

  context 'lambda_versions' do
    it 'return lambda versions without error' do
      dummy_client = double(Aws::Lambda::Client)
      allow(AwsHelper).to receive(:_lambda_client).and_return(dummy_client)
      allow(dummy_client).to receive(:list_versions_by_function).with(:function_name => "function")
                                                                .and_raise(Aws::Lambda::Errors::ResourceNotFoundException.new("some error", nil))
      expect { AwsHelper.lambda_versions(function_name: 'function') }.not_to raise_exception
    end

    it 'fail gracefully when lambda function missing' do
      dummy_client = double(Aws::Lambda::Client)
      allow(AwsHelper).to receive(:_lambda_client).and_return(dummy_client)
      allow(dummy_client).to receive(:list_versions_by_function).with(:function_name => "function").and_return(nil)
      expect { AwsHelper.lambda_versions(function_name: 'function') }.not_to raise_exception
    end

    it 'return lambda versions without error' do
      dummy_client = double(Aws::Lambda::Client)
      allow(AwsHelper).to receive(:_lambda_client).and_return(dummy_client)
      allow(dummy_client).to receive(:list_versions_by_function).with(:function_name => "function")
                                                                .and_raise(ActionError)
      expect { AwsHelper.lambda_versions(function_name: 'function') }.to raise_exception(RuntimeError)
    end
  end

  context 'lambda_invoke' do
    it 'successfully executes' do
      dummy_client = double(Aws::Lambda::Client)
      allow(AwsHelper).to receive(:_lambda_client).and_return(dummy_client)
      allow(dummy_client).to receive(:invoke)
      expect { AwsHelper.lambda_invoke(function_name: 'function') }.not_to raise_exception
    end

    it 'fails to execute' do
      dummy_client = double(Aws::Lambda::Client)
      allow(AwsHelper).to receive(:_lambda_client).and_return(dummy_client)
      allow(dummy_client).to receive(:invoke).and_raise(StandardError)
      expect { AwsHelper.lambda_invoke(function_name: 'function') }.to raise_exception(StandardError)
    end
  end

  context 'lambda_add_permission' do
    it 'successfully executes' do
      dummy_client = double(Aws::Lambda::Client)
      allow(AwsHelper).to receive(:_lambda_client).and_return(dummy_client)
      allow(dummy_client).to receive(:add_permission)
      expect {
        AwsHelper.lambda_add_permission(
          function_name: 'function',
          principal: 'role',
          action: 'lambda:invoke',
          statement_id: 'testing',
          source_account: '123456789',
          source_arn: '123456789',
          qualifier: 'arn:aws:lambda:aws-region:acct-id:function:function-name:2'
        )
      }      .not_to raise_exception
    end

    it 'fails to execute' do
      dummy_client = double(Aws::Lambda::Client)
      allow(AwsHelper).to receive(:_lambda_client).and_return(dummy_client)
      allow(dummy_client).to receive(:add_permission).and_raise(StandardError)
      expect {
        AwsHelper.lambda_add_permission(
          function_name: 'function',
          principal: 'role',
          action: 'lambda:invoke',
          statement_id: 'testing',
          source_account: '123456789',
          source_arn: '123456789',
          qualifier: 'arn:aws:lambda:aws-region:acct-id:function:function-name:2'
        )
      }      .to raise_exception(RuntimeError, /Unable to execute lambda add permission for function function/)
    end
  end

  context 'lambda_get_policy' do
    it 'successfully executes' do
      dummy_client = double(Aws::Lambda::Client)
      allow(AwsHelper).to receive(:_lambda_client).and_return(dummy_client)
      allow(dummy_client).to receive(:get_policy)
      expect {
        AwsHelper.lambda_get_policy(
          function_name: 'function'
        )
      }      .not_to raise_exception
    end

    it 'testing ResourceNotFoundException execution' do
      dummy_client = double(Aws::Lambda::Client)
      allow(AwsHelper).to receive(:_lambda_client).and_return(dummy_client)
      allow(dummy_client).to receive(:get_policy).and_raise(Aws::Lambda::Errors::ResourceNotFoundException.new("some error", nil))
      expect(Log).to receive(:debug).with(/Unable to retrieve the policy for the lambda function test-function/)
      expect {
        AwsHelper.lambda_get_policy(
          function_name: 'test-function'
        )
      }      .not_to raise_exception
    end

    it 'testing execution fails' do
      dummy_client = double(Aws::Lambda::Client)
      allow(AwsHelper).to receive(:_lambda_client).and_return(dummy_client)
      allow(dummy_client).to receive(:get_policy).and_raise(StandardError)

      expect {
        AwsHelper.lambda_get_policy(
          function_name: 'test-function'
        )
      }      .to raise_exception /Failed to retrieve the policy for the lambda function test-function - StandardError/
    end
  end
end
