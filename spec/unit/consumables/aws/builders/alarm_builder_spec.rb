$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws/builders")
require "alarm_builder"

RSpec.describe AlarmBuilder do
  before(:context) do
    @dummy_class = DummyClass.new
    @dummy_class.extend(AlarmBuilder)
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))
  end

  context "._process_alarms" do
    it "updates template when valid inputs are passed on" do
      mocks = @test_data["_process_alarms"]["Mocks"]
      mocks.each { |mock|
        allow(Kernel.const_get(mock["Object"])).to receive_message_chain(mock["MessageChain"]) .and_return(mock["Return"])
      }

      template = @test_data["_process_alarms"]["template"]
      alarms = @test_data["_process_alarms"]["alarm_definitions"]

      expect {
        @dummy_class._process_alarms(
          template: template,
          alarm_definitions: alarms
        )
      } .not_to raise_error

      expect(template).to eq @test_data["_process_alarms"]["Output"]
    end
  end
end # RSpec.describe
