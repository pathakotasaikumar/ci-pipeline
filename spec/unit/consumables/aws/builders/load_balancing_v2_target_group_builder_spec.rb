$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws/builders")
require 'load_balancing_v2_target_group_builder'

RSpec.describe LoadBalancingV2TargetGroupBuilder do
  before(:context) do
    @dummy_class = DummyClass.new
    @dummy_class.extend(LoadBalancingV2TargetGroupBuilder)
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))
  end

  context '._process_load_balancer_v2_target_group' do
    it 'updates template when valid inputs are passed on' do
      @test_data['UnitTest']['Input']['Configurations'].each_with_index do |configuration, index|
        template = { 'Resources' => {}, 'Outputs' => {} }
        target_group = {}

        configuration.each do |name, resource|
          next unless resource['Type'] == 'AWS::ElasticLoadBalancingV2::TargetGroup'

          target_group[name] = resource
        end

        allow(Context).to receive_message_chain('component.replace_variables')

        expect {
          @dummy_class._process_load_balancing_v2_target_group(
            template: template,
            target_group_definition: target_group,
            vpc_id: 'dummy-vpc'
          )
        }.not_to raise_error

        expect(template).to eq @test_data['UnitTest']['Output']['_process_load_balancer_v2_target_group'][index]
      end
    end
  end
end # RSpec.describe
