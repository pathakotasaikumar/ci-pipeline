$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws")
require 'builders/pipeline_backup_policy_builder'
require 'builders/security_rule_builder'
require 'json'

RSpec.describe PipelineBackupPolicyBuilder do
  before(:context) do
    test_data_file = "#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"
    @test_data = (YAML.load_file test_data_file)['UnitTest']
    @dummy_class = DummyClass.new
    @dummy_class.extend(PipelineBackupPolicyBuilder)
  end

  context '_process_backup_policy' do
    it 'successfully executes' do
      allow(Defaults).to receive(:backup_engine_topic_name).and_return('dummy_sns_topic')

      template = { 'Resources' => {}, 'Outputs' => {} }

      @dummy_class._process_backup_policy(
        template: template,
        backup_policy: @test_data['Input']['_process_backup_policy']['Valid'][0]
      )

      expect(template.to_hash).to eq(@test_data['Output']['_process_backup_policy']['Valid'][0].to_hash)
    end

    it 'fails with Unable to resolve engine sns topic arn from' do
      allow(Defaults).to receive(:backup_engine_topic_name).and_return(nil)

      template = { 'Resources' => {}, 'Outputs' => {} }

      expect {
        @dummy_class._process_backup_policy(
          template: template,
          backup_policy: @test_data['Input']['_process_backup_policy']['Valid'][0]
        )
      }.to raise_exception /Unable to resolve engine sns topic arn from/
    end
  end

  context '_validate_account_alias' do
    it 'successfully executes - @dr' do
      expect(@dummy_class._validate_account_alias('@dr')).to eq('@ams01-dr-nonp')
    end

    it 'successfully executes - @dr-nonp' do
      expect(@dummy_class._validate_account_alias('@dr')).to eq('@ams01-dr-nonp')
    end

    it 'successfully executes - @ams01-dr-nonp' do
      expect(@dummy_class._validate_account_alias('@ams01-dr-nonp')).to eq('@ams01-dr-nonp')
    end

    it 'successfully executes - @ams01-origin-nonp' do
      expect(@dummy_class._validate_account_alias('@nonp')).to eq('@ams01-origin-nonp')
    end

    it 'fails to execute, with Invalid value @unknown specified for the account alias' do
      expect {
        @dummy_class._validate_account_alias('@unknown')
      }.to raise_exception /Invalid value @unknown specified for the account alias/
    end
  end

  context '_validate_recurrence' do
    it 'successfully executes' do
      expect { @dummy_class._validate_recurrence('30 8 ? * *') }.not_to raise_exception
    end

    it 'successfully executes , copy targets present' do
      expect { @dummy_class._validate_recurrence('30 8 ? * *', true) }.not_to raise_exception
    end

    it 'fails to execute, Unsupported - extra stanza' do
      expect {
        @dummy_class._validate_recurrence('30 8 ? * * *')
      }.to raise_exception /Unsupported schedule expression/
    end

    it 'fails to execute, Unsupported - copy targets present' do
      expect {
        @dummy_class._validate_recurrence('30 * ? * *', true)
      }.to raise_exception /Unsupported schedule expression/
    end

    it 'fails to execute, Must specify ? for either - day-of-month or day-of-week' do
      expect {
        @dummy_class._validate_recurrence('30 8 ? * ?', true)
      }.to raise_exception("Must specify '?' for either - day-of-month or day-of-week")
    end
  end
end # RSpec.describe
