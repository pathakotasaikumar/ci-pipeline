$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws/builders")
require 'launch_configuration_builder'

RSpec.describe LaunchConfigurationBuilder do
  before(:context) do
    @dummy_class = DummyClass.new
    @dummy_class.extend(LaunchConfigurationBuilder)
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))
  end

  context '._process_launch_configuration' do
    it 'updates template when valid inputs are passed on' do
      @test_data['UnitTest']['Input']['Configurations'].each_with_index do |configuration, index|
        template = @test_data['UnitTest']['Input']['Template']
        ami_id = @test_data['UnitTest']['Input']['AMI']
        user_data = @test_data['UnitTest']['Input']['UserData']
        security_group_ids = @test_data['UnitTest']['Input']['SGs']
        launch_configuration = {}

        configuration.each do |name, resource|
          launch_configuration[name] = resource if resource['Type'] == 'AWS::AutoScaling::LaunchConfiguration'
        end

        expect {
          @dummy_class._process_launch_configuration(
            template: template,
            launch_configuration_definition: launch_configuration,
            image_id: ami_id,
            platform: :amazon_linux,
            user_data: user_data,
            security_group_ids: security_group_ids,
            instance_profile: { "Ref" => "InstanceProfile" },
            metadata: { pre_prepare: "Metadata here", auth: { "MyAuth" => "Test" } },
          )
        }.not_to raise_error
        expect(template).to eq @test_data['UnitTest']['Output']['_process_launch_configuration'][index]
      end
    end
  end
end # RSpec.describe
