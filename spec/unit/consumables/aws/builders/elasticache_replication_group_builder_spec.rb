$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws/builders")
require "elasticache_replication_group_builder"

RSpec.describe ElastiCacheReplicationGroupBuilder do
  before(:context) do
    @dummy_class = DummyClass.new
    @dummy_class.extend(ElastiCacheReplicationGroupBuilder)
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))
  end

  context "._process_elasticache_replication_group" do
    it "updates template with ElastiCacheParameterGroup" do
      replication_group =
        template = { "Resources" => {}, "Outputs" => {} }
      @dummy_class._process_elasticache_replication_group(
        template: template,
        component_name: @test_data["_process_elasticache_replication_group"]["component_name"],
        replication_group: @test_data["_process_elasticache_replication_group"]["replication_group"],
        parameter_group_name: @test_data["_process_elasticache_replication_group"]["parameter_group_name"],
        subnet_group_name: @test_data["_process_elasticache_replication_group"]["subnet_group_name"],
        security_group_ids: @test_data["_process_elasticache_replication_group"]["security_group_ids"]
      )

      expect(template).to eq @test_data["_process_elasticache_replication_group"]["OutputTemplate"]
    end
  end
end # RSpec.describe
