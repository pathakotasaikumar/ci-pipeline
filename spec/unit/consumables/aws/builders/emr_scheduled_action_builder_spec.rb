$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws")
require 'builders/emr_scheduled_action_builder'
require 'json'

RSpec.describe EMRScheduledActionBuilder do
  include EMRScheduledActionBuilder

  before(:context) do
    @dummy_class = DummyClass.new
    @dummy_class.extend(EMRScheduledActionBuilder)
    @component_name = "emr"
    @test_input = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))["UnitTest"]["Input"]
    @test_output = JSON.parse(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.json"))["UnitTest"]["Output"]
    Context.environment.set_variables("aws_account_id" => "123456789012")
    Context.component.set_variables("emr", "MyTaskGroup1Id" => "J-12345789")
    Context.component.set_variables("emr", "MyTaskGroup2Id" => "J-98765544")
    Context.component.set_variables("emr", "MyClusterId" => "J-98765544")
  end

  context '_parse_emr_scheduled_action' do
    (0..3).each do |index|
      it "returns a list of emr scheduled actions - #{index}" do
        scheduled_actions = _parse_emr_scheduled_action(
          definitions: @test_input["_parse_emr_scheduled_action"][index],
          cluster: { "Ref" => "MyCluster" }
        )
        expect(scheduled_actions.to_hash).to eq @test_output["_parse_emr_scheduled_action"][index].to_hash
      end
    end
  end

  context '_process_emr_scheduled_actions' do
    it 'successful executes' do
      allow(@dummy_class).to receive(:_process_pipeline_scheduled_actions)
      expect {
        @dummy_class._process_emr_scheduled_actions(
          template: {},
          scheduled_actions: {},
          execution_role_arn: "dummy-role"
        )
      } .not_to raise_error
    end
  end
end # RSpec.describe
