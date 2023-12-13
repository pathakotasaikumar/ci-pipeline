$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}"))
require 'lib/consumables/aws/aws_rds'
require 'lib/defaults'
require 'lib/runner'

RSpec.describe "AwsRds", :skip => true do
  # due to recent changes in RDS,
  # this integration testing is failing to get private subnets
  # devs will investigate later

  before(:context) do
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))["IntegrationTest"]
    component_name = @test_data["ComponentName"]
    component = @test_data["ComponentDefinition"]["Valid"]["MyRds"]
    @aws_rds = AwsRds.new(component_name, component)
  end

  # context 'RDS sg creator' do
  # it 'RDS testing stack creator' do
  #   Log.info "Run only if you need to create some stack for isolation testing"
  #   expect{
  #   load File.expand_path("#{BASE_DIR}/tasks/deploy.rake")
  #   load File.expand_path("#{BASE_DIR}/tasks/teardown.rake")
  #   log_info()
  #   Dir.chdir "pipeline/test/data/aws_rds_spec_" do
  #     log_info()
  #     allow(AwsHelper) .to receive(:s3_download_object)
  #     Rake::Task['deploy'].invoke
  #   end
  #   }.not_to raise_error
  # end
  # end

  context 'AwsRds.deploy' do
    it 'creates RDS stack with DBInstance and creates dns record with component_dns' do
      allow(Context).to receive(:component).and_call_original
      allow(Context).to receive(:asir).and_call_original
      allow(Context).to receive_message_chain("component.sg_id").with('Test-Component', 'SecurityGroup').and_return("sg-ba24a1de")
      allow(Context).to receive_message_chain("asir.destination_sg_id").and_return("sg-ac24a1c8")

      expect { @aws_rds.deploy }.not_to raise_error
    end
  end

  context 'AwsRds.release' do
    it 'and creates dns record with endpoint' do
      expect { @aws_rds.release }.not_to raise_error
    end
  end

  context 'AwsRds.teardown' do
    it 'deletes RDS stack and updates dns record with delete action' do
      expect { @aws_rds.teardown }.not_to raise_error
    end
  end
end
