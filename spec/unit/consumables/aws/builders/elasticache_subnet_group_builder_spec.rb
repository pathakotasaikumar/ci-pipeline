$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws/builders")
require "elasticache_subnet_group_builder"

RSpec.describe ElastiCacheSubnetGroupBuilder do
  before(:context) do
    @dummy_class = DummyClass.new
    @dummy_class.extend(ElastiCacheSubnetGroupBuilder)
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))
  end

  context "._process_elasticache_subnet_group" do
    it "updates template with ElastiCacheParameterGroup" do
      allow(Context).to receive_message_chain("environment.subnet_ids").and_return(["subnet-123", "subnet-456"])

      subnet_group = @test_data["_process_elasticache_subnet_group"]["subnet_group"]
      template = { "Resources" => {}, "Outputs" => {} }
      @dummy_class._process_elasticache_subnet_group(template: template, subnet_group: subnet_group)

      expect(template).to eq @test_data["_process_elasticache_subnet_group"]["OutputTemplate"]
    end
  end
end # RSpec.describe
