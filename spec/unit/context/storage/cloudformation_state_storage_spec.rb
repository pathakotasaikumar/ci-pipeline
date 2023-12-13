$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib/context/storage"))
require 'cloudformation_state_storage'

RSpec.describe CloudFormationStateStorage do
  before(:context) do
  end

  def _get_storage_client
    CloudFormationStateStorage.new
  end

  context '.initialize' do
    it 'can create instance' do
      CloudFormationStateStorage.new
    end
  end

  context '.save' do
    it 'skips stack delelection if context is nil and stack does not exist' do
      path = 'some-path'
      context = nil

      client = _get_storage_client

      allow(client).to receive(:_stack_name).and_return("aws-stack-name")
      allow(AwsHelper).to receive(:cfn_stack_exists).and_return(nil)
      allow(AwsHelper).to receive(:cfn_delete_stack)

      expect { client.save(path, context) }.not_to raise_error
    end

    it 'deletes stack if context is nil' do
      path = 'some-path'
      context = nil

      client = _get_storage_client

      allow(client).to receive(:_stack_name).and_return("aws-stack-name")
      allow(AwsHelper).to receive(:cfn_stack_exists).and_return("existing-stack-id")
      allow(AwsHelper).to receive(:cfn_delete_stack)

      expect { client.save(path, context) }.not_to raise_error
    end

    it 'creates new stack' do
      path = 'some-path'
      context = {}

      client = _get_storage_client

      allow(client).to receive(:_stack_name).and_return("aws-stack-name")
      allow(AwsHelper).to receive(:cfn_stack_exists).and_return(nil)
      allow(AwsHelper).to receive(:cfn_delete_stack)
      allow(AwsHelper).to receive(:cfn_create_stack)

      expect { client.save(path, context) }.not_to raise_error
    end

    it 'updates existing stack' do
      path = 'some-path'
      context = {}

      client = _get_storage_client

      allow(client).to receive(:_stack_name).and_return("aws-stack-name")
      allow(AwsHelper).to receive(:cfn_stack_exists).and_return('my-stack')
      allow(AwsHelper).to receive(:cfn_delete_stack)
      allow(AwsHelper).to receive(:cfn_update_stack)

      expect { client.save(path, context) }.not_to raise_error
    end

    it 'raises on stack save error' do
      path = 'some-path'
      context = {}

      client = _get_storage_client

      allow(client).to receive(:_stack_name).and_return("aws-stack-name")
      allow(AwsHelper).to receive(:cfn_stack_exists).and_return('my-stack')
      allow(AwsHelper).to receive(:cfn_delete_stack)
      allow(AwsHelper).to receive(:cfn_update_stack).and_raise('cannot save stack')

      expect { client.save(path, context) }.to raise_error(/cannot save stack/)
    end
  end

  context '._get_stack_template' do
    it 'returns stack template' do
      client = _get_storage_client

      metadata_value = "test"
      template = client.__send__(
        :_get_stack_template,
        context: metadata_value
      )

      expect(template).not_to be(nil)
      expect(template).not_to be({
        'Resources' => {
          'Storage' => {
            'Type' => 'AWS::CloudFormation::WaitConditionHandle',
            'Metadata' => metadata_value
          }
        }
      })
    end
  end

  context '._stack_name' do
    it 'returns stack name' do
      path = ['p1', 'p2']
      client = _get_storage_client

      expect(client.__send__(:_stack_name, path)).to eq(path.join('-'))
    end
  end

  context '.load' do
    it 'returns reraise on loading error (stack exists)' do
      path = 'some-path'
      client = _get_storage_client

      allow(client).to receive(:_stack_name).and_return("aws-stack-name")
      allow(AwsHelper).to receive(:cfn_get_template).and_raise('error')

      expect {
        client.load(path)
      }.to raise_error(/error/)
    end

    it 'returns nil on loading error (stack does not exist)' do
      path = 'some-path'
      client = _get_storage_client

      allow(client).to receive(:_stack_name).and_return("aws-stack-name")
      allow(AwsHelper).to receive(:cfn_get_template).and_raise('stack does not exist')

      expect(client.load(path)).to eq(nil)
    end

    it 'returns nil on empty stack values' do
      path = 'some-path'
      client = _get_storage_client

      allow(client).to receive(:_stack_name).and_return("aws-stack-name")

      resource = {}
      allow(AwsHelper).to receive(:cfn_get_template).and_return(resource)
      expect(client.load(path)).to eq(nil)

      resource = {
        "Resources" => {}
      }
      allow(AwsHelper).to receive(:cfn_get_template).and_return(resource)
      expect(client.load(path)).to eq(nil)

      resource = {
        "Resources" => {
          "Storage" => {}
        }
      }
      allow(AwsHelper).to receive(:cfn_get_template).and_return(resource)
      expect(client.load(path)).to eq(nil)
    end

    it 'returns metadata section of stack value' do
      path = 'some-path'
      client = _get_storage_client

      allow(client).to receive(:_stack_name)

      resource = {
        "Resources" => {
          "Storage" => {
            "Metadata" => {
              'a' => '1'
            }
          }
        }
      }

      allow(AwsHelper).to receive(:cfn_get_template).and_return(resource)
      expect(client.load(path)).to eq({
        'a' => '1'
      })
    end
  end
end
