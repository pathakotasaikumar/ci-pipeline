$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws/builders")
require 'amq_configuration_builder'

RSpec.describe 'AmqConfigurationBuilder' do
  before(:context) do
    @dummy_class = DummyClass.new
    @dummy_class.extend(AmqConfigurationBuilder)
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))['UnitTest']
  end

  context '._process_amq_configuration_builder' do
    it 'should generate AMQ Broker configuration template' do
      template = { 'Resources' => {}, 'Outputs' => {} }
      broker_configuration = @test_data['Input']['amq_Configuration']['Configuration']

      @dummy_class._process_amq_configuration_builder(
        template: template,
        component_name: 'amqconfiguration',
        amq_configuration: broker_configuration
      )

      expect(template).to eq @test_data['Output']
    end
  end
end
