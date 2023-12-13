$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws/builders")
require 'db_option_group_builder'

RSpec.describe DbOptionGroupBuilder do
  before(:context) do
    @dummy_class = DummyClass.new
    @dummy_class.extend(DbOptionGroupBuilder)
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))['UnitTest']
    Context.component.set_variables('test', {
      'SecuritySecurityGroupId' => 'sg-123'
    })
    Context.component.set_variables('_asir', {
      'DestinationSecurityGroupId' => 'sg-456',
      'SourceSecurityGroupId' => 'sg-789'
    })
  end

  context '._process_db_option_group' do
    it 'builds template related to option group' do
      @test_data['Input']['Definitions'].each_with_index { |db_option_group, index|
        template = { "Resources" => {}, "Outputs" => {} }
        @dummy_class._process_db_option_group(
          template: template,
          component_name: 'test',
          db_option_groups: db_option_group,
          db_option_groups_deletionpolicy: "Delete"
        )
        expect(template).to eq @test_data['Output']['_process_db_option_group'][index]
      }
    end
  end

  context '._process_settings_password' do
    it 'should decrypt settings password' do
      settings_definition = {
        "Name" => 'test',
        "Value" => 'encryptedpassword'
      }

      allow(Context).to receive_message_chain('component.replace_variables')
      allow(AwsHelper).to receive(:kms_decrypt_data)

      expect {
        @dummy_class._process_settings_password(
          settings_definition: settings_definition
        )
      }.not_to raise_error
    end

    it 'should raise KMS Decrypt exception' do
      settings_definition = {
        "Name" => 'test',
        "Value" => 'encryptedpassword'
      }

      allow(AwsHelper).to receive(:kms_decrypt_data).and_raise(ActionError)

      expect {
        @dummy_class._process_settings_password(
          settings_definition: settings_definition
        )
      }.to raise_error(RuntimeError, /Failed to process the RDS Option Group Settings password/)
    end
  end
end # RSpec.describe
