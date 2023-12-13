$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws/builders")
require "kinesis_stream_builder"

RSpec.describe KinesisStreamBuilder do
  before(:context) do
    @dummy_class = DummyClass.new
    @dummy_class.extend(KinesisStreamBuilder)
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))
  end

  context "._process_kinesis_stream" do
    it "generates Kinesis stream definition" do
      allow(Context).to receive_message_chain('kms.secrets_key_arn')
        .and_return('arn:aws:kms:ap-southeast-2:111122223333:key/1234abcd-12ab-34cd-56ef-1234567890ab')

      template = { "Resources" => {}, "Outputs" => {} }
      expect {
        @dummy_class._process_kinesis_stream(
          template: template,
          stream: @test_data["_process_kinesis_stream"]["stream"],
          component_name: @test_data["_process_kinesis_stream"]["component_name"],
        )
      }.not_to raise_error

      expect(template).to eq @test_data["_process_kinesis_stream"]["OutputTemplate"]
    end
  end
end
