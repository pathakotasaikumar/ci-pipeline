$LOAD_PATH.unshift("#{BASE_DIR}/lib")
require "consumables/aws/builders/ecs_service_builder"
require "util/obj_to_text"
require "util/user_data"

RSpec.describe ECSServiceBuilder do
  before(:context) do
    @dummy_class = DummyClass.new
    @dummy_class.extend(ECSServiceBuilder)
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))
  end

  context "._process_ecs_service" do
    it "update template on valid definition input" do
      template = { "Resources" => {} }
      comp_name = "DummyComponent"
      service_definition = @test_data["UnitTest"]["Input"]["_process_ecs_service"]

      allow(Context).to receive_message_chain("component.sg_id").and_return('sg-12345')
      allow(Context).to receive_message_chain("environment.subnet_ids").and_return(['subnet-123'])
      allow(Context).to receive_message_chain("component.replace_variables").and_return(service_definition.values[0]['Properties']['LoadBalancers'])
      allow(Context).to receive_message_chain("component.variable").with(comp_name, 'ECSContainerName').and_return('DummyContainerName')

      @dummy_class._process_ecs_service(
        template: template,
        component_name: comp_name,
        task_definition_logical_name: "DummyTaskDefinition",
        service_definition: service_definition
      )
      expect(template).to eq(@test_data["UnitTest"]["Output"]["_process_ecs_service"])
    end
  end
end # RSpec.describe
