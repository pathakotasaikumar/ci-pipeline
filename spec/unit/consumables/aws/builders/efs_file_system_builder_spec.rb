$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws/builders")
require 'efs_file_system_builder'

RSpec.describe EfsFileSystemBuilder do
  before(:context) do
    @dummy_class = DummyClass.new
    @dummy_class.extend(EfsFileSystemBuilder)
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))['UnitTest']
  end

  context '._process_efs_file_systems' do
    it 'updates template - auto populates missing properties' do
      template = @test_data['Input']['Template']
      allow(Context).to receive_message_chain('kms.secrets_key_arn').and_return('arn:aws:kms:ap-southeast-2:111122223333:key/1234abcd-12ab-34cd-56ef-1234567890ab')
      @dummy_class._process_efs_file_systems(
        template: template,
        file_system_definitions: @test_data['Input']['Configuration']['Minimal']
      )
      expect(template).to eq @test_data['Output']['_process_queue']['Minimal']
    end
  end
end # RSpec.describe
