$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws/builders")
require 'efs_mount_target_builder'

RSpec.describe EfsMountTargetBuilder do
  before(:context) do
    @dummy_class = DummyClass.new
    @dummy_class.extend(EfsMountTargetBuilder)
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))['UnitTest']
  end

  context '._process_mount_target' do
    it 'updates template - auto populates missing properties' do
      template = @test_data['Input']['Template']
      @dummy_class._process_efs_mount_targets(
        template: template,
        mount_target_definitions: @test_data['Input']['Configuration']['Minimal']
      )
      expect(template).to eq @test_data['Output']['_process_queue']['Minimal']
    end
  end
end # RSpec.describe
