$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws")
require 'aws_autoscale'

RSpec.describe AwsAutoscale, :skip => true do
  # skipped due to the fact, autoscale now requires user-data processing in the instance and hence cannot be tested in isolation.

  before(:context) do
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))['IntegrationTest']
    @component_name = @test_data['Input']['ComponentName']
    @awsAutoscale = AwsAutoscale.new(@component_name, @test_data['Input']['Valid'])
  end

  context '.deploy' do
    it 'deploys component successfully' do
      allow(AwsHelper).to receive(:s3_copy_object)
      allow(Context).to receive(:component).and_call_original
      allow(Context).to receive(:asir).and_call_original
      allow(Context).to receive(:kms).and_call_original

      allow(Context).to receive_message_chain("component.sg_id").with('my-webtier', 'AsgSecurityGroup').and_return("sg-ba24a1de")
      allow(Context).to receive_message_chain("component.sg_id").with('my-webtier', 'ElbSecurityGroup').and_return("sg-ba24a1de")
      allow(Context).to receive_message_chain("asir.set_name").and_return("latest")
      allow(Context).to receive_message_chain("asir.source_sg_id").and_return("sg-asir-source")
      allow(Context).to receive_message_chain("asir.destination_sg_id").and_return("sg-e30b8c87")
      allow(Context).to receive_message_chain("kms.secrets_key_arn").and_return("arn:aws:cloudformation:ap-southeast-2:695837244598:stack/ams01-c001-01-prod-kms/17e1fa90-27ad-11e6-a573-50fae94face6")

      expect {
        @awsAutoscale.deploy
      }.not_to raise_error
    end
  end

  context '.release_component' do
    it 'updates dns record' do
      expect { @awsAutoscale.release }.not_to raise_error
    end
  end

  context '.teardown' do
    it 'deletes stack and dns record' do
      expect { @awsAutoscale.teardown }.not_to raise_error
    end
  end
end # RSpec.describe
