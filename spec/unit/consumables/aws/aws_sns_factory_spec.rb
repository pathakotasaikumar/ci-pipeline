$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws")
require 'aws_sns_factory'

RSpec.describe AwsSnsFactory do
  # include InstanceBuilder
  before(:context) do
    @test_data = YAML.load(
      File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"),
      permitted_classes: ['IamSecurityRule']
    )['UnitTest']
    @component_name = @test_data['Input']['ComponentName']
    @sns_factory_name = @test_data['Input']['Initialize']['Valid']['Configuration'].keys.first
  end

  context '.initialize' do
    it 'initialize without error' do
      expect {
        AwsSnsFactory.new(@component_name, @test_data['Input']['Initialize']['Valid'])
      }.not_to raise_exception

      expect {
        AwsSnsFactory.new(@component_name, @test_data['Input']['Initialize']['Invalid'])
      }.to raise_exception(RuntimeError)
    end
  end

  context '.security_items' do
    it 'returns security items' do
      aws_sns_factory = AwsSnsFactory.new(@component_name, @test_data['Input']['Initialize']['Valid'])
      expect(aws_sns_factory.security_items).to eq @test_data['Output']['SecurityItems']
    end
  end

  context '.security_rules' do
    it 'returns security rules' do
      dummy_topic_arn = 'arn:aws:sns:ap-southeast-2:111111111111:ams01-c031-99-dev-master-5-TestComponent'
      dummy_platform_app_arn = 'arn:aws:sns:ap-southeast-2:111111111111:app/*/ams01-c031'
      dummy_platform_endpoint_arn = 'arn:aws:sns:ap-southeast-2:111111111111:endpoint/*/ams01-c031'
      allow(Context).to receive_message_chain('component.variable').with(@component_name, "#{@sns_factory_name}TopicArnPrefix").and_return(dummy_topic_arn)
      allow(Context).to receive_message_chain('component.variable').with(@component_name, "#{@sns_factory_name}PlatformAppArnPrefix").and_return(dummy_platform_app_arn)
      allow(Context).to receive_message_chain('component.variable').with(@component_name, "#{@sns_factory_name}PlatformEndpointArnPrefix").and_return(dummy_platform_endpoint_arn)

      aws_sns_factory = AwsSnsFactory.new(@component_name, @test_data['Input']['Initialize']['Valid'])
      expect(aws_sns_factory.security_rules).to eq @test_data['Output']['SecurityRules']
    end
  end

  context '.deploy' do
    it 'deploys stack' do
      aws_sns_factory = AwsSnsFactory.new(@component_name, @test_data['Input']['Initialize']['Valid'])

      allow(aws_sns_factory).to receive(:_full_template)
      allow(AwsHelper).to receive(:cfn_create_stack)
      allow(Context).to receive_message_chain('component.set_variables')

      expect { aws_sns_factory.deploy }.not_to raise_exception
    end
  end

  context '.release' do
    it 'releases stack' do
      aws_sns_factory = AwsSnsFactory.new(@component_name, @test_data['Input']['Initialize']['Valid'])

      expect { aws_sns_factory.release }.not_to raise_exception
    end
  end

  context '.teardown' do
    it 'deletes stack' do
      aws_sns_factory = AwsSnsFactory.new(@component_name, @test_data['Input']['Initialize']['Valid'])

      allow(AwsHelper).to receive(:cfn_delete_stack)

      expect { aws_sns_factory.teardown }.not_to raise_exception
    end
  end
end # RSpec.describe
