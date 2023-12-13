$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws")
require 'builders/pipeline_db_cluster_backup_policy_builder'
require 'builders/security_rule_builder'
require 'json'

RSpec.describe PipelineDbClusterBackupPolicyBuilder do
  before(:context) do
    test_data_file = "#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"
    Log.debug test_data_file
    @test_data = (YAML.load_file test_data_file)['UnitTest']
    @dummy_class = DummyClass.new
    @dummy_class.extend(PipelineDbClusterBackupPolicyBuilder)
  end

  context '_parse_db_cluster_backup_policy' do
    (0..0).each do |index|
      it "returns a list of db cluster backup policies - #{index}" do
        allow(Context).to receive_message_chain('environment.account_id').and_return('012345678912')
        allow(Context).to receive_message_chain('environment.region').and_return('ap-southeast-2')
        allow(Context).to receive_message_chain('environment.variable').and_return('dummy-engine-address')
        allow(Defaults).to receive(:txt_by_dns).and_return('dummy_sns_topic')
        backup_policy = @dummy_class._parse_db_cluster_backup_policy(
          component_name: 'dbcluster',
          definitions: @test_data['Input']['_parse_db_cluster_backup_policy']['Valid'][index],
          resource_id: 'a1234567890'
        )
        expect(backup_policy.to_hash).to eq(@test_data['Output']['_parse_db_cluster_backup_policy']['Valid'][index].to_hash)
      end
    end
  end
end # RSpec.describe
