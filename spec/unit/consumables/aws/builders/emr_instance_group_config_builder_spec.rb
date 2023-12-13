$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws/builders")
require "emr_instance_group_config_builder"

RSpec.describe EmrInstanceGroupConfigBuilder do
  before(:context) do
    @dummy_class = DummyClass.new
    @dummy_class.extend(EmrInstanceGroupConfigBuilder)
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))
  end

  context "._process_emr_instance_group_configs" do
    it "generates EMR step definitions" do
      template = { "Resources" => {}, "Outputs" => {} }
      expect {
        @dummy_class._process_emr_instance_group_configs(
          template: template,
          component_name: "cluster",
          instance_group_config_definitions: @test_data["_process_emr_instance_group_configs"]["instance_group_config_definitions"],
          cluster_name: @test_data["_process_emr_instance_group_configs"]["cluster_name"],
        )
      }.not_to raise_error

      expect(template).to eq @test_data["_process_emr_instance_group_configs"]["OutputTemplate"]
    end
  end
end
