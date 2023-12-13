$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws/builders")
require 'application_autoscaling_builder'

RSpec.describe ApplicationAutoscalingBuilder do
  before(:context) do
    @dummy_class = DummyClass.new
    @dummy_class.extend(ApplicationAutoscalingBuilder)
    @test_data = YAML.load(
      File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"),
      permitted_classes: ['IamSecurityRule']
    )
    @component_name = File.basename(__FILE__, '.yaml')
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

  context '._process_application_autoscaling_group' do
    it 'updates template when valid inputs are passed on' do
      @test_data['UnitTest']['Input']['_process_autoscaling_group'].each_with_index do |configuration, index|
        template = Marshal.load(Marshal.dump(@test_data['UnitTest']['Input']['Template']))
        scalable_target = {}
        scaling_policy = {}

        configuration.each do |name, resource|
          scalable_target[name] = resource if resource['Type'] == 'AWS::ApplicationAutoScaling::ScalableTarget'
          scaling_policy[name] = resource if resource['Type'] == 'AWS::ApplicationAutoScaling::ScalingPolicy'
        end

        expect {
          @dummy_class._process_application_autoscaling_group(
            template: template,
            component_name: @component_name,
            scalable_target: scalable_target,
            scaling_policy: scaling_policy,
            service_name_space: 'dynamodb',
            service_role_arn: 'service-role-arn'
          )
        }.not_to raise_error

        compare_hash("", @test_data['UnitTest']['Output']['_process_autoscaling_group'][index], template)
      end
    end

    # We check the target method later on, just need to cover the logic
    it 'calls non-dynamodb target' do
      @test_data['UnitTest']['Input']['_process_autoscaling_group'].each_with_index do |configuration, index|
        template = Marshal.load(Marshal.dump(@test_data['UnitTest']['Input']['Template']))
        scalable_target = {}
        scaling_policy = {}

        configuration.each do |name, resource|
          scalable_target[name] = resource if resource['Type'] == 'AWS::ApplicationAutoScaling::ScalableTarget'
          scaling_policy[name] = resource if resource['Type'] == 'AWS::ApplicationAutoScaling::ScalingPolicy'
        end

        expect {
          @dummy_class._process_application_autoscaling_group(
            template: template,
            component_name: @component_name,
            scalable_target: scalable_target,
            scaling_policy: scaling_policy,
            service_name_space: 'ecs',
            service_role_arn: 'service-role-arn'
          )
        }.not_to raise_error
      end
    end
  end

  context '._process_application_autoscaling_targets_dynamodb' do
    it 'raise error on invalid resource id' do
      template = Marshal.load(Marshal.dump(@test_data['UnitTest']['Input']['Template']))
      scalable_target = @test_data['UnitTest']['Input']['_process_application_autoscaling_targets_dynamodb']['invalid_resource_id']

      expect {
        @dummy_class._process_application_autoscaling_targets_dynamodb(
          template: template,
          scalable_target: scalable_target,
          service_name_space: 'dynamodb',
          service_role_arn: 'service-role-arn'
        )
      }.to raise_error(/Resource id value cannot be empty and must be array/)
    end

    it 'process targets successfully' do
      template = Marshal.load(Marshal.dump(@test_data['UnitTest']['Input']['Template']))
      scalable_target = @test_data['UnitTest']['Input']['_process_application_autoscaling_targets_dynamodb']['valid']

      expect {
        @dummy_class._process_application_autoscaling_targets_dynamodb(
          template: template,
          scalable_target: scalable_target,
          service_name_space: 'dynamodb',
          service_role_arn: 'service-role-arn'
        )
      }.not_to raise_error
      expect(template).to eq(@test_data['UnitTest']['Output']['_process_application_autoscaling_targets_dynamodb']['valid'])
    end
  end

  context '._process_application_autoscaling_targets' do
    it 'process ECS targets successfully' do
      template = Marshal.load(Marshal.dump(@test_data['UnitTest']['Input']['Template']))
      scalable_target = @test_data['UnitTest']['Input']['_process_application_autoscaling_targets']['ecs']

      expect {
        @dummy_class._process_application_autoscaling_targets(
          template: template,
          scalable_target: scalable_target,
          service_name_space: 'ecs',
          resource_id: @test_data['UnitTest']['Input']['_process_application_autoscaling_targets']['ecs_resource_id']
        )
      }.not_to raise_error
      expect(template).to eq(@test_data['UnitTest']['Output']['_process_application_autoscaling_targets']['ecs'])
    end
  end

  context '._process_application_autoscaling_policies' do
    it 'process Step Scaling successfully' do
      template = Marshal.load(Marshal.dump(@test_data['UnitTest']['Input']['Template']))
      scaling_policy = @test_data['UnitTest']['Input']['_process_application_autoscaling_policies']['StepScaling']

      allow(Defaults).to receive(:resource_name).and_return('dummy-resource-name')
      expect {
        @dummy_class._process_application_autoscaling_policies(
          template: template,
          component_name: @component_name,
          scaling_policy: scaling_policy,
          resource_id: @test_data['UnitTest']['Input']['_process_application_autoscaling_targets']['ecs_resource_id']
        )
      }.not_to raise_error
      expect(template).to eq(@test_data['UnitTest']['Output']['_process_application_autoscaling_policies']['StepScaling'])
    end
  end

  context '._dynamodb_autoscaling_security_rules' do
    it 'return the security rule' do
      expect(@dummy_class._dynamodb_autoscaling_security_rules(
               component_name: 'correct'
             )).to eq @test_data['UnitTest']['Output']['security_rules']
    end
  end
end # RSpec.describe
