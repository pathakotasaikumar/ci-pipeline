$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws/builders")
require "events_rule_builder"

RSpec.describe EventsRuleBuilder do
  before(:context) do
    @dummy_class = DummyClass.new
    @dummy_class.extend(EventsRuleBuilder)
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))
  end

  context "._process_events_rule" do
    it "generates Events Rule definitions" do
      allow(Context).to receive_message_chain('component.replace_variables').and_return('compvar1value')

      template = { "Resources" => {}, "Outputs" => {} }
      expect {
        @dummy_class._process_events_rule(
          template: template,
          definitions: @test_data['Input']
        )
      }.not_to raise_error

      expect(template).to eq @test_data['Output']
    end

    it "generates Events Rule Json Input" do
      allow(Context).to receive_message_chain('component.replace_variables').and_return('compvar1value')

      template = { "Resources" => {}, "Outputs" => {} }
      expect {
        @dummy_class._process_events_rule(
          template: template,
          definitions: @test_data['JsonInput']
        )
      }.not_to raise_error

      expect(template).to eq @test_data['JsonOutput']
    end

    it "fails in invalid target_arn" do
      allow(Context).to receive_message_chain('component.replace_variables').and_return('compvar1value')

      template = { "Resources" => {}, "Outputs" => {} }
      expect {
        @dummy_class._process_events_rule(
          template: template,
          definitions: @test_data['Invalid']
        )
      }.to raise_error(/specified for rule Target Arn/)
    end
  end
end
