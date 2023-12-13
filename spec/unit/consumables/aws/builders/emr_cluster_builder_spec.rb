$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws/builders")
require "emr_cluster_builder"

RSpec.describe EmrClusterBuilder do
  before(:context) do
    @dummy_class = DummyClass.new
    @dummy_class.extend(EmrClusterBuilder)
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))

    Context.component.set_variables("emrfs-db", { "TableName" => "emrfs-db-TableName" })
  end

  context "._process_emr_cluster" do
    it "generates EMR cluster definition" do
      allow(Context).to receive_message_chain("environment.subnet_ids").and_return(["subnet-123", "subnet-456"])
      allow(Context).to receive_message_chain("environment.variable").with("aws_proxy_host", nil).and_return("proxy.test.com")
      allow(Context).to receive_message_chain("environment.variable").with("aws_proxy_port", nil).and_return("1234")
      allow(Context).to receive_message_chain("environment.variable").with("aws_no_proxy_wildcards", "").and_return("localhost,no-proxy-test")

      template = { "Resources" => {}, "Outputs" => {} }
      expect {
        @dummy_class._process_emr_cluster(
          template: template,
          cluster_definition: @test_data["_process_emr_cluster"]["cluster_definition"],
          component_name: @test_data["_process_emr_cluster"]["component_name"],
          job_role: @test_data["_process_emr_cluster"]["job_role"],
          master_security_group_id: @test_data["_process_emr_cluster"]["master_security_group_id"],
          slave_security_group_id: @test_data["_process_emr_cluster"]["slave_security_group_id"],
          service_security_group_id: @test_data["_process_emr_cluster"]["service_security_group_id"],
          additional_master_security_group_ids: @test_data["_process_emr_cluster"]["additional_master_security_group_ids"],
          additional_slave_security_group_ids: @test_data["_process_emr_cluster"]["additional_slave_security_group_ids"],
        )
      }.not_to raise_error

      expect(template).to eq @test_data["_process_emr_cluster"]["OutputTemplate"]
    end
  end
end
