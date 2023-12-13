$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws/builders")
require 'db_parameter_group_builder'

RSpec.describe DbParameterGroupBuilder do
  before(:context) do
    @dummy_class = DummyClass.new
    @dummy_class.extend(DbParameterGroupBuilder)
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))['UnitTest']
  end
  context '._process_db_parameter_groups' do
    it 'updates template with DBParameterGroup' do
      @test_data['Input']['Definition'].each_with_index { |definition, index|
        template = { "Resources" => {}, "Outputs" => {} }
        @dummy_class._process_db_parameter_groups(template: template, db_parameter_groups: definition)
        expect(template).to eq @test_data['Output']['_process_db_parameter_groups'][index]
        template.clear
      }
    end
  end
end # RSpec.describe
