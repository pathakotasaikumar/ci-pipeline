$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws/builders")
require "elasticache_parameter_group_builder"

RSpec.describe ElastiCacheParameterGroupBuilder do
  before(:context) do
    @dummy_class = DummyClass.new
    @dummy_class.extend(ElastiCacheParameterGroupBuilder)
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))
  end

  context "._process_elasticache_parameter_group" do
    it "updates template with ElastiCacheParameterGroup" do
      parameter_group = @test_data["_process_elasticache_parameter_group"]["parameter_group"]
      template = { "Resources" => {}, "Outputs" => {} }
      @dummy_class._process_elasticache_parameter_group(template: template, parameter_group: parameter_group)

      expect(template).to eq @test_data["_process_elasticache_parameter_group"]["OutputTemplate"]
    end
  end
end # RSpec.describe
