$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws/builders")
require 'instance_profile_builder'

RSpec.describe InstanceProfileBuilder do
  before(:context) do
    @dummy_class = DummyClass.new
    @dummy_class.extend(InstanceProfileBuilder)
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))
  end

  context '._process_instance_profile' do
    it 'updates template when valid inputs are passed on' do
      template = { 'Resources' => {}, 'Outputs' => {} }
      expect {
        @dummy_class._process_instance_profile(
          template: template,
          instance_role_name: "InstanceRoleName-123",
        )
      }.not_to raise_error
      expect(template).to eq @test_data['UnitTest']['Output']['_process_instance_profile']
    end
  end
end # RSpec.describe
