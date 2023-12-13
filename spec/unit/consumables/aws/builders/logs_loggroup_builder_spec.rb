$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws/builders")
require "logs_loggroup_builder"

RSpec.describe LogsLoggroupBuilder do
  before(:context) do
    @dummy_class = DummyClass.new
    @dummy_class.extend(LogsLoggroupBuilder)
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))
  end

  context "._process_logs_loggroup" do
    it "generates LogGroup definition" do
      template = { "Resources" => {}, "Outputs" => {} }

      expect {
        @dummy_class._process_logs_loggroup(
          template: template,
          definitions: @test_data["_process_logs_loggroup"]['Input']
        )
      }.not_to raise_error

      expect(template).to eq @test_data["_process_logs_loggroup"]['Output']
    end
  end
end
