$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws/builders")
require 'autoscaling_group_builder'

RSpec.describe AutoscalingGroupBuilder do
  before(:context) do
    @dummy_class = DummyClass.new
    @dummy_class.extend(AutoscalingGroupBuilder)
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))
  end

  def compare_hash(path, expected, actual)
    expect("#{path} class = #{actual.class}").to eq("#{path} class = #{expected.class}")

    expected.each do |key, value|
      if value.is_a? Hash
        compare_hash("#{path}.#{key}", value, actual[key])
      else
        expect("#{path}.#{key} = #{actual[key]}").to eq("#{path}.#{key} = #{value}")
      end
    end
  end

  context '._process_autoscaling_group' do
    it 'updates template when valid inputs are passed on' do
      allow(Context).to receive_message_chain("environment.subnet_ids").and_return(["subnet-123", "subnet-456"])

      @test_data['UnitTest']['Input']['Configurations'].each_with_index do |configuration, index|
        template = @test_data['UnitTest']['Input']['Template']
        autoscaling_group = {}
        load_balancer = {}
        launch_configuration = {}
        launch_template_configuration = {}
        platform = :rhel
        configuration.each do |name, resource|
          autoscaling_group[name] = resource if resource['Type'] == 'AWS::AutoScaling::AutoScalingGroup'
          launch_configuration[name] = resource if resource['Type'] == 'AWS::AutoScaling::LaunchConfiguration'
          launch_template_configuration[name] = resource if resource['Type'] == 'AWS::EC2::LaunchTemplate'
          load_balancer[name] = resource if resource['Type'] == 'AWS::ElasticLoadBalancing::LoadBalancer'
        end

        expect {
          @dummy_class._process_autoscaling_group(
            template: template,
            platform: platform,
            autoscaling_group_definition: autoscaling_group,
            launch_configuration_name: launch_configuration.keys[0],
            launch_template_name: launch_template_configuration.keys[0],
            load_balancer_name: load_balancer.keys[0]
          )
        }.not_to raise_error

        compare_hash("", @test_data['UnitTest']['Output']['_process_autoscaling_group'][index], template)
        expect {
          @dummy_class._process_autoscaling_group(
            template: template,
            platform: platform,
            autoscaling_group_definition: autoscaling_group,
            launch_configuration_name: launch_configuration.keys[0],
            launch_template_name: launch_template_configuration.keys[0],
            load_balancer_name: load_balancer.keys[0],
            wait_condition_name: "waitcondition"
          )
        }.not_to raise_error

        compare_hash("", @test_data['UnitTest']['Output']['_process_autoscaling_group_with_waitcondition'][index], template)
      end
    end
  end
end # RSpec.describe
