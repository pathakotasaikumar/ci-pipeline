$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws")
require 'builders/pipeline_volume_backup_policy_builder'
require 'builders/security_rule_builder'
require 'json'

RSpec.describe PipelineVolumeBackupPolicyBuilder do
  before(:context) do
    test_data_file = "#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"
    Log.debug test_data_file
    @test_data = (YAML.load_file test_data_file)['UnitTest']
    @dummy_class = DummyClass.new
    @dummy_class.extend(PipelineVolumeBackupPolicyBuilder)
  end

  context '_parse_volume_backup_policy' do
    (0..0).each do |index|
      it "returns a list of volume backup policies - #{index}" do
        allow(Context).to receive_message_chain('environment.account_id').and_return('012345678912')
        allow(Context).to receive_message_chain('environment.region').and_return('ap-southeast-2')
        allow(Context).to receive_message_chain('environment.variable').and_return('dummy-engine-address')
        allow(AwsHelper).to receive(:ssm_get_parameter).and_return('dummy')
        allow(Defaults).to receive(:txt_by_dns).and_return('dummy_sns_topic')
        backup_policy = @dummy_class._parse_volume_backup_policy(
          component_name: 'volume',
          definitions: @test_data['Input']['_parse_volume_backup_policy']['Valid'][index],
          resource_id: 'vol-01234567890'
        )
        Log.debug YAML.dump(backup_policy.to_hash)

        expect(backup_policy.to_hash).to eq(@test_data['Output']['_parse_volume_backup_policy']['Valid'][index].to_hash)
      end
    end
  end
end # RSpec.describe
