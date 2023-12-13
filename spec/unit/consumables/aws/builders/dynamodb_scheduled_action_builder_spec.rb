$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws")
require 'builders/dynamodb_scheduled_action_builder'
require 'builders/security_rule_builder'
require 'json'

RSpec.describe DynamoDBScheduledActionBuilder do
  include PipelineScheduledActionBuilder

  before(:context) do
    test_data_file = "#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"
    Log.debug test_data_file
    @test_data = (YAML.load_file test_data_file)['UnitTest']
    @dummy_class = DummyClass.new
    @dummy_class.extend(DynamoDBScheduledActionBuilder)
  end

  context '_parse_dynamodb_scheduled_action' do
    (0..3).each do |index|
      it "returns a list of dynamodb scheduled actions - #{index}" do
        scheduled_actions = @dummy_class._parse_dynamodb_scheduled_action(
          definitions: @test_data['Input']['_parse_dynamodb_scheduled_action']['Valid'][index]
        )
        expect(scheduled_actions.to_hash).to eq @test_data['Output']['_parse_dynamodb_scheduled_action']['Valid'][index].to_hash
      end
    end

    it 'fails with - Unknown schedule expression' do
      expect {
        @dummy_class._parse_dynamodb_scheduled_action(
          definitions: @test_data['Input']['_parse_dynamodb_scheduled_action']['Invalid'][0]
        )
      }.to raise_error /Unknown schedule expression/
    end

    it 'fails with - Must specify \'?\' for either - day-of-month or day-of-week' do
      expect {
        @dummy_class._parse_dynamodb_scheduled_action(
          definitions: @test_data['Input']['_parse_dynamodb_scheduled_action']['Invalid'][1]
        )
      }.to raise_error /Must specify .* for either - day-of-month or day-of-week/
    end

    it 'fails with - Invalid read capacity count' do
      expect {
        @dummy_class._parse_dynamodb_scheduled_action(
          definitions: @test_data['Input']['_parse_dynamodb_scheduled_action']['Invalid'][2]
        )
      }.to raise_error /Invalid read capacity count/
    end

    it 'fails with - Invalid write capacity count' do
      expect {
        @dummy_class._parse_dynamodb_scheduled_action(
          definitions: @test_data['Input']['_parse_dynamodb_scheduled_action']['Invalid'][3]
        )
      }.to raise_error /Invalid write capacity count/
    end

    it 'fails with - TableName is a required property for Pipeline::DynamoDB::ScheduledAction resource' do
      expect {
        @dummy_class._parse_dynamodb_scheduled_action(
          definitions: @test_data['Input']['_parse_dynamodb_scheduled_action']['Invalid'][4]
        )
      }.to raise_error /TableName is a required property for Pipeline::DynamoDB::ScheduledAction resource/
    end
  end

  context '_process_dynamodb_scheduled_actions' do
    it 'returns template for dynamodb scheduled actions resources' do
      template = { "Resources" => {}, "Outputs" => {} }
      allow(@dummy_class).to receive(:_process_pipeline_scheduled_actions)
      expect {
        @dummy_class._process_dynamodb_scheduled_actions(
          template: template,
          scheduled_actions: {},
          execution_role_arn: 'dummy'
        )
      }.to_not raise_exception
    end

    it 'fails with argument error' do
      template = { "Resources" => {}, "Outputs" => {} }
      allow(@dummy_class).to receive(:_process_pipeline_scheduled_actions)
      expect {
        @dummy_class._process_dynamodb_scheduled_actions(
          template: template
        )
      }.to raise_exception(ArgumentError)
    end
  end

  context 'dynamodb_scheduled_action_security_rules' do
    it 'returns security rules' do
      expect(@dummy_class._dynamodb_scheduled_action_security_rules(
               component_name: 'dummy'
             )).to be_a(Array)
    end

    it 'fails with argument error' do
      expect {
        @dummy_class._dynamodb_scheduled_action_security_rules
      }.to raise_exception(ArgumentError)
    end
  end

  context '_dynamodb_scheduled_action_security_items' do
    it 'returns security items' do
      expect(@dummy_class._dynamodb_scheduled_action_security_items(
               component_name: 'dummy'
             )).to be_a(Array)
    end

    it 'fails with argument error' do
      expect {
        @dummy_class._dynamodb_scheduled_action_security_items
      }.to raise_exception(ArgumentError)
    end
  end
end # RSpec.describe
