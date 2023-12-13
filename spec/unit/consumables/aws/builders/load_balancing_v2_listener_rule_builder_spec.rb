$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws/builders")
require 'load_balancing_v2_listener_rule_builder'

RSpec.describe LoadBalancingV2ListenerRuleBuilder do
  before(:context) do
    @dummy_class = DummyClass.new
    @dummy_class.extend(LoadBalancingV2ListenerRuleBuilder)
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))
  end

  context '._process_load_balancer_v2_listener_rule' do
    it 'updates template when valid inputs are passed on' do
      @test_data['UnitTest']['Input']['Configurations'].each_with_index do |configuration, index|
        template = { 'Resources' => {}, 'Outputs' => {} }
        listener_rule = {}

        configuration.each do |name, resource|
          next if resource['Type'] != 'AWS::ElasticLoadBalancingV2::ListenerRule'

          listener_rule[name] = resource
        end

        expect {
          @dummy_class._process_load_balancing_v2_listener_rule(
            template: template,
            listener_rule_definition: listener_rule
          )
        }.not_to raise_error

        expect(template).to eq @test_data['UnitTest']['Output']['_process_load_balancer_v2_listener_rule'][index]
      end
    end
  end
end # RSpec.describe
