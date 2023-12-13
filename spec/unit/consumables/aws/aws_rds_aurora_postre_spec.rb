$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws")
require 'aws_rds_aurora_postgre'

RSpec.describe AwsRdsAuroraPostgre do
  before(:context) do
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/aws_rds_aurora_postgre_spec.yaml"))['UnitTest']
  end

  def _get_aurora_instance
    component_name = @test_data['ComponentName']
    valid_components = @test_data['ComponentDefinition']['Valid'].values

    AwsRdsAurora.new(component_name, valid_components.first)
  end

  context '.initialize' do
    it 'initialises without error' do
      @test_data['ComponentDefinition']['Valid'].values.each { |definition, index|
        expect { AwsRdsAurora.new(@test_data['ComponentName'], definition, "aurora-postgresql") }.not_to raise_error
      }
    end
  end

  context '._get_port_from_engine_name' do
    it 'returns value' do
      component = _get_aurora_instance

      expect(component.__send__(:_get_port_from_engine_name, 'aurora-postgresql')).to eq('5432')

      expect {
        component.__send__(:_get_port_from_engine_name, 'aurora1')
      }.to raise_error(/Unknown engine name/)
    end
  end
end # RSpec.describe
