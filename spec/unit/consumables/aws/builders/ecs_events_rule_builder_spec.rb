$LOAD_PATH.unshift("#{BASE_DIR}/lib")
require "consumables/aws/builders/ecs_events_rule_builder"
require "util/obj_to_text"
require "util/user_data"

RSpec.describe ECSEventsRuleBuilder do
  before(:context) do
    @dummy_class = DummyClass.new
    @dummy_class.extend(ECSEventsRuleBuilder)
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))
  end

  context "._process_ecs_events_rule" do
    it "update template on valid definition input" do
      template = { "Resources" => {} }
      component_name = "DummyComponentName"
      event_definition = @test_data["UnitTest"]["Input"]["_process_ecs_events_rule"]
      allow(Defaults).to receive(:component_stack_name).and_return('dummy-stack-name')
      allow(Context).to receive_message_chain("component.role_arn").with(component_name, "ExecutionRole").and_return("DummyExecutionRole")
      allow(Context).to receive_message_chain("component.role_arn").with(component_name, "TaskRole").and_return("DummyTaskRole")
      allow(Context).to receive_message_chain("component.sg_id").and_return("sg-123")
      allow(Context).to receive_message_chain("environment.subnet_ids").and_return(["subnet-123", "subnet-456"])
      allow(Context).to receive_message_chain("component.replace_variables")
      @dummy_class._process_ecs_events_rule(
        component_name: component_name,
        rule_name: "DummyRuleName",
        template: template,
        task_definition_logical_name: "DummyTaskName",
        event_definition: event_definition
      )
      Log.debug("output: #{template}")
      expect(template).to eq(@test_data["UnitTest"]["Output"]["_process_ecs_events_rule"])
    end
  end
end # RSpec.describe
