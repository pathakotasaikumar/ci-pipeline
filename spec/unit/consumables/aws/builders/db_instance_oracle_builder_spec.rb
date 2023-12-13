$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws")
require 'builders/db_instance_oracle_builder'
require 'util/generate_password'
require_relative 'db_instance_spec_helper'

RSpec.describe DbInstanceOracleBuilder do
  include DbInstanceOracleBuilder
  include DbInstanceSpecHelper

  before(:context) do
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))["UnitTest"]
  end

  context 'AwsRdsOracle._process_db_instances' do
    it 'returns db instances template for OracleMinimal' do
      template = { 'Resources' => {}, 'Outputs' => {} }
      allow(Context).to receive_message_chain('kms.secrets_key_arn').and_return('kms-dummy')
      db_template = @test_data["ComponentDefinition"]["Valid"]["OracleMinimal"]["Configuration"]["Database"]
      expected_template = @test_data["TestResult"]["OracleMinimal"]

      _process_db_instances(
        template: template,
        db_instance_definitions: { "Database" => db_template },
        db_parameter_group: { 'DummyParameterGroup' => {} },
        db_option_group: { 'DummyOptionGroup' => {} },
        snapshot_identifier: nil,
        security_group_ids: ["sg123"],
        component_name: "DBInstance"
      )

      expect(template).to eq expected_template
      _validate_db_login template, expected_template
    end

    it 'returns db instances template for OracleMinimal with oracle-se1' do
      template = { 'Resources' => {}, 'Outputs' => {} }
      allow(Context).to receive_message_chain('kms.secrets_key_arn').and_return('kms-dummy')
      db_template = @test_data["ComponentDefinition"]["Valid"]["OracleMinimalSe1"]["Configuration"]["Database"]
      expected_template = @test_data["TestResult"]["OracleMinimalSe1"]

      _process_db_instances(
        template: template,
        db_instance_definitions: { "Database" => db_template },
        db_parameter_group: {},
        db_option_group: {},
        snapshot_identifier: nil,
        security_group_ids: ["sg123"],
        component_name: "DBInstance"
      )

      expect(template).to eq expected_template
      _validate_db_login template, expected_template
    end

    it 'returns db instances template for OracleSnapshot' do
      template = { 'Resources' => {}, 'Outputs' => {} }
      allow(Context).to receive_message_chain('kms.secrets_key_arn').and_return('kms-dummy')
      db_template = @test_data["ComponentDefinition"]["Valid"]["OracleSnapshot"]["Configuration"]["Database"]
      expected_template = @test_data["TestResult"]["OracleSnapshot"]

      _process_db_instances(
        template: template,
        db_instance_definitions: { "Database" => db_template },
        db_parameter_group: {},
        db_option_group: {},
        snapshot_identifier: nil,
        security_group_ids: ["sg123"],
        component_name: "DBInstance"
      )

      expect(template).to eq expected_template
      _validate_db_login template, expected_template
    end

    it 'returns db instances template for OracleOverride' do
      template = { 'Resources' => {}, 'Outputs' => {} }
      allow(Context).to receive_message_chain('kms.secrets_key_arn').and_return('kms-dummy')
      db_template = @test_data["ComponentDefinition"]["Valid"]["OracleOverride"]["Configuration"]["Database"]
      expected_template = @test_data["TestResult"]["OracleOverride"]

      _process_db_instances(
        template: template,
        db_instance_definitions: { "Database" => db_template },
        db_parameter_group: {},
        db_option_group: {},
        snapshot_identifier: nil,
        security_group_ids: ["sg123"],
        component_name: "DBInstance"
      )

      expect(template).to eq expected_template
      _validate_db_login template, expected_template
    end

    it 'returns db instances template for specific snapshot' do
      template = { 'Resources' => {}, 'Outputs' => {} }
      allow(Context).to receive_message_chain('kms.secrets_key_arn').and_return('kms-dummy')
      db_template = @test_data["ComponentDefinition"]["Valid"]["OracleSpecificSnapshot"]["Configuration"]["Database"]
      expected_template = @test_data["TestResult"]["OracleSpecificSnapshot"]

      _process_db_instances(
        template: template,
        db_instance_definitions: { "Database" => db_template },
        db_parameter_group: {},
        db_option_group: {},
        snapshot_identifier: "Snapshot-old",
        security_group_ids: ["sg123"],
        component_name: "DBInstance"
      )

      expect(template).to eq expected_template
      _validate_db_login template, expected_template
    end

    it 'returns db instances template for latest snapshot' do
      template = { 'Resources' => {}, 'Outputs' => {} }
      allow(Context).to receive_message_chain('kms.secrets_key_arn').and_return('kms-dummy')
      db_template = { "Database" => @test_data["ComponentDefinition"]["Valid"]["OracleLatestSnapshot"]["Configuration"]["Database"] }
      expected_template = @test_data["TestResult"]["OracleLatestSnapshot"]

      _process_db_instances(
        template: template,
        db_instance_definitions: db_template,
        db_parameter_group: {},
        db_option_group: {},
        snapshot_identifier: "lastest-snap-xx",
        security_group_ids: ["sg123"],
        component_name: "DBInstance"
      )
      expect(template).to eq expected_template
      _validate_db_login template, expected_template
    end

    it 'throws exception when invalid engine is specified' do
      template = { 'Resources' => {}, 'Outputs' => {} }
      allow(Context).to receive_message_chain('kms.secrets_key_arn').and_return('kms-dummy')
      expect {
        _process_db_instances(
          template: template,
          db_instance_definitions: { "Database" => @test_data["ComponentDefinition"]["Invalid"]["Engine"]["Configuration"]["Database"] },
          db_parameter_group: {},
          db_option_group: {},
          security_group_ids: ["sg123"],
          component_name: "DBInstance"
        )
      }.to raise_error(RuntimeError, /Unsupported database engine/)
    end

    it 'fails with DBName must start with ...' do
      template = { 'Resources' => {}, 'Outputs' => {} }
      allow(Context).to receive_message_chain('kms.secrets_key_arn').and_return('kms-dummy')
      db_template = @test_data["ComponentDefinition"]["Invalid"]["BadName"]["Configuration"]["Database"]
      expect {
        _process_db_instances(
          template: template,
          db_instance_definitions: { "Database" => db_template },
          db_parameter_group: {},
          db_option_group: {},
          snapshot_identifier: nil,
          security_group_ids: ["sg123"],
          component_name: "DBInstance"
        )
      }.to raise_exception /DBName must start with/
    end

    it 'throws exception when db name is not specified' do
      template = { 'Resources' => {}, 'Outputs' => {} }
      allow(Context).to receive_message_chain('kms.secrets_key_arn').and_return('kms-dummy')
      expect {
        _process_db_instances(
          template: template,
          db_instance_definitions: { "Database" => @test_data["ComponentDefinition"]["Invalid"]["DBName"]["Configuration"]["Database"] },
          db_parameter_group: {},
          db_option_group: {},
          security_group_ids: ["sg123"],
          component_name: "DBInstance"
        )
      }.to raise_error(RuntimeError, /Could not find property at path/)
    end
  end
end # RSpec.describe
