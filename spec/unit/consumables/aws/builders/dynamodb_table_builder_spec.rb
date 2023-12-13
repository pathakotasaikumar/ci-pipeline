$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws/builders")
require "dynamodb_table_builder"

RSpec.describe DynamoDbTableBuilder do
  before(:context) do
    @dummy_class = DummyClass.new
    @dummy_class.extend(DynamoDbTableBuilder)
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))
  end

  context "._process_dynamodb_table" do
    it "generates DynamoDB table definition" do
      template = { "Resources" => {}, "Outputs" => {} }
      expect {
        @dummy_class._process_dynamodb_table(
          template: template,
          component_name: "checkpoint-db",
          table_definition: @test_data["_process_dynamodb_table"]["table_definition"],
        )
      }.not_to raise_error

      expect(template).to eq @test_data["_process_dynamodb_table"]["OutputTemplateCurrent"]
    end
    it "generates DynamoDB table definition ondemand" do
      billing_mode = @test_data["_process_dynamodb_table"]["table_definition_ondemand"]["MyTable"]["Properties"]["BillingMode"]
      template = { "Resources" => {}, "Outputs" => {} }
      expect {
        @dummy_class._process_dynamodb_table(
          template: template,
          component_name: "checkpoint-db",
          table_definition: @test_data["_process_dynamodb_table"]["table_definition_ondemand"],
          billing_mode: billing_mode
        )
      }.not_to raise_error

      expect(template).to eq @test_data["_process_dynamodb_table"]["OutputTemplateOndemand"]
    end
  end
end
