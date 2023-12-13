$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws/builders")
require "emr_step_builder"

RSpec.describe EmrStepBuilder do
  before(:context) do
    @dummy_class = DummyClass.new
    @dummy_class.extend(EmrStepBuilder)
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))
  end

  context "._process_emr_steps" do
    it "generates EMR step definitions" do
      allow(Context).to receive_message_chain('component', 'replace_variables').and_return('compvar1value')

      template = { "Resources" => {}, "Outputs" => {} }
      expect {
        @dummy_class._process_emr_steps(
          template: template,
          step_definitions: @test_data["_process_emr_steps"]["step_definitions"],
          cluster_name: @test_data["_process_emr_steps"]["cluster_name"]
        )
      }.not_to raise_error

      expect(template).to eq @test_data["_process_emr_steps"]["OutputTemplate"]
    end
  end
end
