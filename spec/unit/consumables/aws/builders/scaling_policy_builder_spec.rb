$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws/builders")
require 'scaling_policy_builder'

RSpec.describe ScalingPolicyBuilder do
  before(:context) do
    @dummy_class = DummyClass.new
    @dummy_class.extend(ScalingPolicyBuilder)
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))['UnitTest']
  end
  context '._process_scaling_policies' do
    it 'updates template when valid inputs are passed on' do
      @test_data['Input']['Configurations'].each_with_index do |configuration, index|
        template = @test_data['Input']['Template']
        scaling_policies = {}
        autoscaling_group = {}

        configuration.each do |name, resource|
          autoscaling_group[name] = resource if resource['Type'] == 'AWS::AutoScaling::AutoScalingGroup'
          scaling_policies[name] = resource if resource['Type'] == 'AWS::AutoScaling::ScalingPolicy'
        end

        expect {
          @dummy_class._process_scaling_policies(
            template: template,
            scaling_policy_definitions: scaling_policies,
            autoscaling_group_name: autoscaling_group.keys[0]
          )
        }.not_to raise_error
        expect(template).to eq @test_data['Output']['_process_scaling_policies'][index]
      end
    end
  end
end # RSpec.describe
