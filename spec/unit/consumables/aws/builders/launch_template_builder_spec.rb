$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws/builders")
require 'launch_template_builder'

RSpec.describe LaunchConfigurationBuilder do
  before(:context) do
    @dummy_class = DummyClass.new
    @dummy_class.extend(LaunchTemplateBuilder)
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))
  end

  context '._process_launch_template_configuration' do
    it 'updates template when valid inputs are passed on' do
      @test_data['UnitTest']['Input']['Configurations'].each_with_index do |configuration, index|
        template = @test_data['UnitTest']['Input']['Template']
        ami_id = @test_data['UnitTest']['Input']['AMI']
        user_data = @test_data['UnitTest']['Input']['UserData']
        security_group_ids = @test_data['UnitTest']['Input']['SGs']
        launch_template_definition = {}

        configuration.each do |name, resource|
          launch_template_definition[name] = resource if resource['Type'] == 'AWS::EC2::LaunchTemplate'
        end

        expect {
          @dummy_class._process_launch_template_configuration(
            template: template,
            launch_template_definition: launch_template_definition,
            image_id: ami_id,
            platform: :amazon_linux,
            user_data: user_data,
            security_group_ids: security_group_ids,
            instance_profile: { "Ref" => "InstanceProfile" },
            metadata: { pre_prepare: "Metadata here", auth: { "MyAuth" => "Test" } },
          )
        }.not_to raise_error
        expect(template).to eq @test_data['UnitTest']['Output']['_process_launch_template_configuration'][index]
      end
    end
  end
end # RSpec.describe
