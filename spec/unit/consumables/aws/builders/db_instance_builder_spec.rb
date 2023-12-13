$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws")
require 'builders/db_instance_builder'

RSpec.describe DbInstanceBuilder do
  include DbInstanceBuilder

  before(:context) do
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))["UnitTest"]
  end

  context '_process_db_password' do
    it 'Successfully replaced password' do
      db_definition = @test_data["_process_db_password"]["ValidDefinition"]["Configuration"]["Database"]

      allow(Context).to receive_message_chain('component.replace_variables')
      allow(AwsHelper).to receive(:kms_decrypt_data)

      expect {
        _process_db_password(
          definition: db_definition
        )
      }.not_to raise_exception
    end

    it 'Failed to process the RDS Database password' do
      db_definition = @test_data["_process_db_password"]["ValidDefinition"]["Configuration"]["Database"]

      allow(Context).to receive_message_chain('component.replace_variables')
      allow(AwsHelper).to receive(:kms_decrypt_data).and_raise(RuntimeError.new('Cannot fetch KMS key'))

      expect {
        _process_db_password(
          definition: db_definition
        )
      }.to raise_exception(RuntimeError, /Cannot fetch KMS key/)
    end
  end
end # RSpec.describe
