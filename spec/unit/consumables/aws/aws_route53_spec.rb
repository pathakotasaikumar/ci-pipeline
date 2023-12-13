$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws")
require 'aws_route53'

RSpec.describe AwsRoute53 do
  before(:context) do
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/aws_route53_spec.yaml"))['UnitTest']
  end

  def _get_consumable
    @test_data['ComponentDefinition']['Valid'].values.each { |definition, index|
      return AwsRoute53.new(@test_data['ComponentName'], definition)
    }
  end

  context '.initialize' do
    it 'initialises without error' do
      @test_data['ComponentDefinition']['Valid'].values.each { |definition, index|
        expect { AwsRoute53.new(@test_data['ComponentName'], definition) }.not_to raise_error
      }
    end

    it 'raises on unsupported component' do
      expect {
        @test_data['ComponentDefinition']['Invalid'].values.each { |definition, index|
          expect { AwsRoute53.new(@test_data['ComponentName'], definition) }.not_to raise_error
        }
      }.to raise_error(/is not supported by this component/)
    end

    it 'raises on Null type component' do
      expect {
        @test_data['ComponentDefinition']['InvalidNull'].values.each { |definition, index|
          expect { AwsRoute53.new(@test_data['ComponentName'], definition) }.not_to raise_error
        }
      }.to raise_error(/Must specify a type for resource/)
    end
  end

  context '.security_rules' do
    it 'returns value' do
      consumable = _get_consumable

      items = consumable.security_items

      expect(items.class).to be(Array)
      expect(items.count).to eq(0)
    end

    it 'returns value' do
      consumable = _get_consumable

      items = consumable.security_rules

      expect(items.class).to be(Array)
      expect(items.count).to eq(0)
    end
  end

  context '._build_template' do
    it 'returns value' do
      consumable = _get_consumable

      allow(Defaults).to receive(:deployment_dns_name)

      allow(consumable).to receive(:_process_route53_records)
      allow(consumable).to receive(:_process_route53_healthcheck)

      result = consumable.send(:_build_template)

      expect(result.class).to be(Hash)
      expect(result.count).not_to eq(nil)
    end
  end

  context '.name_records' do
    it 'returns value' do
      consumable = _get_consumable

      allow(Defaults).to receive(:deployment_dns_name)

      result = consumable.name_records

      expect(result.class).to be(Hash)
      expect(result.keys.count).to eq(2)

      expect(result.keys.include?("DeployDnsName")).to eq(true)
      expect(result.keys.include?("ReleaseDnsName")).to eq(true)
    end
  end

  context '.deploy' do
    it 'deploys stack' do
      consumable = _get_consumable

      allow(Defaults).to receive(:component_stack_name)
      allow(Defaults).to receive(:get_tags).and_return([])

      allow(consumable).to receive(:_build_template)

      allow(AwsHelper).to receive(:cfn_create_stack)

      allow(Context).to receive_message_chain('component.set_variables')

      result = consumable.deploy
    end

    it 'raise on failed stack' do
      consumable = _get_consumable

      allow(Defaults).to receive(:component_stack_name)
      allow(Defaults).to receive(:get_tags).and_return([])

      allow(consumable).to receive(:_build_template)

      allow(AwsHelper).to receive(:cfn_create_stack) .and_raise(ActionError.new('Cannot deploy r53'))

      allow(Context).to receive_message_chain('component.set_variables')

      expect {
        result = consumable.deploy
      }.to raise_error(/Failed to create stack/)
    end
  end

  context '.teardown' do
    it 'does notning on empty stack' do
      consumable = _get_consumable

      allow(Context).to receive_message_chain('component.stack_id').and_return(nil)
      allow(AwsHelper).to receive(:cfn_delete_stack)

      result = consumable.teardown
    end

    it 'teardown stack' do
      consumable = _get_consumable

      allow(Context).to receive_message_chain('component.stack_id').and_return(1)
      allow(AwsHelper).to receive(:cfn_delete_stack)

      result = consumable.teardown
    end

    it 'raise on failed stack' do
      consumable = _get_consumable

      allow(Context).to receive_message_chain('component.stack_id').and_return(1)
      allow(AwsHelper).to receive(:cfn_delete_stack).and_raise('Failed to delete stack')

      expect {
        result = consumable.teardown
      }.to raise_error(/Failed to delete stack/)
    end
  end

  context '.release' do
    it 'releases' do
      consumable = _get_consumable
      consumable.release
    end
  end
end # RSpec.describe
