$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws/builders")
require 'sqs_queue_builder'

RSpec.describe SqsQueueBuilder do
  before(:context) do
    @dummy_class = DummyClass.new
    @dummy_class.extend(SqsQueueBuilder)
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))['UnitTest']

    Context.environment.set_variables({
      "region" => "ap-southeast-2",
      "aws_account_id" => "123456789012"
    })

    Context.component.set_variables("sqs", { "QueueArn" => "arn:aws:sqs:ap-southeast-2:123456789012:queue1" })
  end

  context '._process_queue' do
    it 'updates template - auto populates missing properties' do
      template = @test_data['Input']['Template']
      @dummy_class._process_queue template: template, queue_definition: @test_data['Input']['Configuration']['Minimal']
      expect(template).to eq @test_data['Output']['_process_queue']['Minimal']
    end

    it 'updates template - populates configured properties' do
      template = @test_data['Input']['Template']
      @dummy_class._process_queue template: template, queue_definition: @test_data['Input']['Configuration']['Versatile']
      expect(template).to eq @test_data['Output']['_process_queue']['Versatile']
    end

    it 'updates template - with dead letter queue' do
      template = @test_data['Input']['Template']
      @dummy_class._process_queue template: template, queue_definition: @test_data['Input']['Configuration']['DLQ']
      expect(template).to eq @test_data['Output']['_process_queue']['DLQ']
    end

    it 'updates template - with fifo queue' do
      template = @test_data['Input']['Template']
      @dummy_class._process_queue template: template, queue_definition: @test_data['Input']['Configuration']['FIFO']
      expect(template).to eq @test_data['Output']['_process_queue']['FIFO']
    end
  end
end # RSpec.describe
