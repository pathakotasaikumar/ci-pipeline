$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws/builders")
require 'db_subnet_group_builder'

RSpec.describe DbSubnetGroupBuilder do
  before(:context) do
    @dummy_class = DummyClass.new
    @dummy_class.extend(DbSubnetGroupBuilder)
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))['UnitTest']
  end

  context '._process_db_subnet_group' do
    it 'updates template db subnet' do
      template = @test_data['Input']['Template']
      @dummy_class.definition = @test_data['Input']['Definition']
      load_mocks @test_data['Input']['Mock']
      @dummy_class._process_db_subnet_group(template: template, db_subnet_group: { "DBSubnetGroup" => {} })
      expect(template).to eq @test_data['Output']['_process_db_subnet_group']
    end
  end
end # RSpec.describe
