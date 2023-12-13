$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws")
require 'builders/instance_scheduled_action_builder'
require 'builders/security_rule_builder'
require 'json'

RSpec.describe InstanceScheduledActionBuilder do
  include PipelineScheduledActionBuilder

  before(:context) do
    test_data_file = "#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"
    Log.debug test_data_file
    @test_data = YAML.load_file(
      test_data_file,
      permitted_classes: ['IamSecurityRule']
    )['UnitTest']
    @dummy_class = DummyClass.new
    @dummy_class.extend(InstanceScheduledActionBuilder)
  end

  context '_parse_ec2_scheduled_actions' do
    (0..3).each do |index|
      it "returns a list of ec2 scheduled actions - #{index}" do
        scheduled_actions = @dummy_class._parse_ec2_scheduled_actions(
          instance_name: 'Instance',
          definitions: @test_data['Input']['_parse_ec2_scheduled_actions']['Valid'][index]
        )
        expect(scheduled_actions.to_hash).to eq @test_data['Output']['_parse_ec2_scheduled_actions']['Valid'][index].to_hash
      end
    end

    it 'fails with - Unknown schedule expression' do
      expect {
        @dummy_class._parse_ec2_scheduled_actions(
          instance_name: 'Instance',
          definitions: @test_data['Input']['_parse_ec2_scheduled_actions']['Invalid'][0]
        )
      }.to raise_error /Unknown schedule expression/
    end

    it 'fails with - Must specify \'?\' for either - day-of-month or day-of-week' do
      expect {
        @dummy_class._parse_ec2_scheduled_actions(
          instance_name: 'Instance',
          definitions: @test_data['Input']['_parse_ec2_scheduled_actions']['Invalid'][1]
        )
      }.to raise_error /Must specify .* for either - day-of-month or day-of-week/
    end

    it 'fails with - Action is a required property for Pipeline::EC2::ScheduledAction' do
      expect {
        @dummy_class._parse_ec2_scheduled_actions(
          instance_name: 'Instance',
          definitions: @test_data['Input']['_parse_ec2_scheduled_actions']['Invalid'][2]
        )
      }.to raise_error /Action is a required property for Pipeline::EC2::ScheduledAction/
    end
  end

  context '_ec2_scheduled_action_security_rules' do
    it 'returns empty array on empty instance_id' do
      instance_id = nil
      allow(Context).to receive_message_chain("component.variable") .and_return(instance_id)

      result = @dummy_class._ec2_scheduled_action_security_rules(
        component_name: 'TestComponent',
        instance_name: 'Instance'
      )

      expect(result).to eq([])
    end

    it 'returns security rules array for instance_id' do
      expected_rules = @test_data['Output']['_ec2_scheduled_action_security_rules']['ValidRules']

      instance_id = 'test-instance-id'
      kms_key_arn = 'test-kmd-key-arn'

      allow(Context).to receive_message_chain("environment.region")      .and_return("ap-southeast-2")
      allow(Context).to receive_message_chain("environment.account_id")  .and_return("1234567890")

      allow(Context).to receive_message_chain("component.variable")  .and_return(instance_id)
      allow(Context).to receive_message_chain("kms.secrets_key_arn") .and_return(kms_key_arn)

      result = @dummy_class._ec2_scheduled_action_security_rules(
        component_name: 'TestComponent',
        instance_name: 'Instance'
      )

      # expet 3 roles
      expect(result.count).to eq(3)
      expect(result).to eq(expected_rules)
    end
  end
end # RSpec.describe
