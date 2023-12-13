$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws/builders")
require 'load_balancing_v2_load_balancer_builder'

RSpec.describe LoadBalancingV2LoadBalancerBuilder do
  before(:context) do
    @dummy_class = DummyClass.new
    @dummy_class.extend(LoadBalancingV2LoadBalancerBuilder)
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))
  end

  context '._process_load_balancer' do
    it 'updates template when valid inputs are passed on' do
      @test_data['UnitTest']['Input']['Configurations'].each_with_index do |configuration, index|
        template = { 'Resources' => {}, 'Outputs' => {} }
        load_balancer = {}
        security_group_ids = ['sg-12345678', 'sg-45678901']

        configuration.each do |name, resource|
          if resource['Type'] == 'AWS::ElasticLoadBalancingV2::LoadBalancer'
            load_balancer[name] = resource
          end
        end

        allow(Context).to receive_message_chain('environment.vpc_id').and_return('vpc-01234567')
        allow(Context).to receive_message_chain('environment.subnet_ids').and_return(['subnet-12345678'])

        expect {
          @dummy_class._process_load_balancing_v2_load_balancer(
            template: template,
            load_balancer_definition: load_balancer,
            security_group_ids: security_group_ids
          )
        }.not_to raise_error

        expect(template).to eq @test_data['UnitTest']['Output']['_process_load_balancer'][index]
      end
    end
  end
end # RSpec.describe
