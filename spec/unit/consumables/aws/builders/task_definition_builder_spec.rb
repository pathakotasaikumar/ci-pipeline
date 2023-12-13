$LOAD_PATH.unshift("#{BASE_DIR}/lib")
require "consumables/aws/builders/task_definition_builder"
require "util/obj_to_text"
require "util/user_data"

RSpec.describe TaskDefinitionBuilder do
  before(:context) do
    @dummy_class = DummyClass.new
    @dummy_class.extend(TaskDefinitionBuilder)
    @test_data = YAML.load(
      File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"),
      permitted_classes: ['IamSecurityRule']
    )
  end

  context "._process_task_definition" do
    it "update template on valid definition input" do
      template = { "Resources" => {} }
      comp_name = "DummyComponent"
      container_definition = @test_data["UnitTest"]["Input"]["_process_task_definition"]["DummyDefinition"]["Properties"]["ContainerDefinitions"]
      allow(Context).to receive_message_chain("component.role_arn").with(comp_name, "ExecutionRole").and_return("DummyExecutionRole")
      allow(Context).to receive_message_chain("component.role_arn").with(comp_name, "TaskRole").and_return("DummyTaskRole")
      allow(Context).to receive_message_chain("component.replace_variables").and_return(container_definition)
      allow(Context).to receive_message_chain("component.set_variables")
      @dummy_class._process_task_definition(
        component_name: comp_name,
        template: template,
        task_definition: @test_data["UnitTest"]["Input"]["_process_task_definition"],
        tags: [
          { key: 'tagkey1', value: 'tagvalue1' }
        ]
      )
      expect(template).to eq(@test_data["UnitTest"]["Output"]["_process_task_definition"])
    end
  end

  context "._execution_base_security_rules" do
    it "returns the default execution role rules" do
      component_name = "TestComponent"
      role_name = "TestRole"
      expect(
        @dummy_class._execution_base_security_rules(
          component_name: component_name,
          role_name: role_name
        )
      ).to eq(@test_data["UnitTest"]["Output"]["_execution_base_security_rules"])
    end
  end

  context "._task_base_security_rules" do
    it "returns the default task role rules" do
      allow(Context).to receive_message_chain("kms.secrets_key_arn").and_return("arn:aws:kms:ap-southeast-2:111122223333:key/dummyarn")
      allow(Context).to receive_message_chain("s3.ams_bucket_arn").and_return("arn:aws:s3:::bucket-ams-test")
      allow(Context).to receive_message_chain("s3.qda_bucket_arn").and_return("arn:aws:s3:::bucket-qda-test")
      allow(Context).to receive_message_chain("s3.as_bucket_arn").and_return("arn:aws:s3:::bucket-as-test")

      component_name = "TestComponent"
      role_name = "TestRole"
      expect(
        @dummy_class._task_base_security_rules(
          component_name: component_name,
          role_name: role_name
        )
      ).to eq(@test_data["UnitTest"]["Output"]["_task_base_security_rules"])
    end
  end
end # RSpec.describe
