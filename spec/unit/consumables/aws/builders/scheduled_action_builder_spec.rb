$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws/builders")
require 'scheduled_action_builder'

RSpec.describe ScheduledActionBuilder do
  before(:context) do
    @dummy_class = DummyClass.new
    @dummy_class.extend(ScheduledActionBuilder)
    @input = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))['Input']
    @output = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))['Output']
  end
  context '._process_scheduled_actions' do
    it 'updates template when valid inputs are passed on' do
      template = { "Resources" => {} }
      scheduled_actions = {}
      autoscaling_group = {}

      @input.each do |name, resource|
        puts name
        autoscaling_group[name] = resource if resource['Type'] == 'AWS::AutoScaling::AutoScalingGroup'
        scheduled_actions[name] = resource if resource['Type'] == 'AWS::AutoScaling::ScheduledAction'
      end

      expect {
        @dummy_class._process_scheduled_actions(
          template: template,
          scheduled_actions: scheduled_actions,
          autoscaling_group_name: autoscaling_group.keys[0]
        )
      }.not_to raise_error
      expect(template).to eq @output
    end
  end
end # RSpec.describe
