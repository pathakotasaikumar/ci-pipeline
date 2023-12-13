$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws")
require 'builders/db_instance_postgresql_builder'
require 'util/generate_password'
require_relative 'db_instance_spec_helper'

RSpec.describe DbInstancePostgresqlBuilder do
  include DbInstancePostgresqlBuilder
  include DbInstanceSpecHelper

  before(:context) do
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))["UnitTest"]
  end

  context 'AwsRdsPostgresql._process_db_instances' do
    it 'returns db instances template for PostgresqlMinimal' do
      template = { 'Resources' => {}, 'Outputs' => {} }
      allow(Context).to receive_message_chain('kms.secrets_key_arn').and_return('kms-dummy')
      db_template = @test_data["ComponentDefinition"]["Valid"]["PostgresqlMinimal"]["Configuration"]["Database"]
      expected_template = @test_data["TestResult"]["PostgresqlMinimal"]

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

    it 'returns db instances template for PostgresqlReplica' do
      template = { 'Resources' => {}, 'Outputs' => {} }
      allow(Context).to receive_message_chain('kms.secrets_key_arn').and_return('kms-dummy')
      db_template = @test_data["ComponentDefinition"]["Valid"]["PostgresqlReplica"]["Configuration"]["Database"]
      expected_template = @test_data["TestResult"]["PostgresqlReplica"]

      _process_db_instances(
        template: template,
        db_instance_definitions: { "Database" => db_template },
        db_parameter_group: {},
        snapshot_identifier: nil,
        security_group_ids: ["sg123"],
        component_name: "DBInstance"
      )

      expect(template).to eq expected_template
      _validate_db_login template, expected_template
    end

    it 'returns db instances template for PostgresqlMinimal' do
      template = { 'Resources' => {}, 'Outputs' => {} }
      allow(Context).to receive_message_chain('kms.secrets_key_arn').and_return('kms-dummy')
      db_template = @test_data["ComponentDefinition"]["Valid"]["PostgresqlParameterGroup"]["Configuration"]["Database"]
      expected_template = @test_data["TestResult"]["PostgresqlParameterGroup"]

      _process_db_instances(
        template: template,
        db_instance_definitions: { "Database" => db_template },
        db_parameter_group: { 'DummyParameterGroup' => {} },
        snapshot_identifier: nil,
        security_group_ids: ["sg123"],
        component_name: "DBInstance"
      )

      expect(template).to eq expected_template
      _validate_db_login template, expected_template
    end

    it 'returns db instances template for PostgresqlSnapshot' do
      template = { 'Resources' => {}, 'Outputs' => {} }
      allow(Context).to receive_message_chain('kms.secrets_key_arn').and_return('kms-dummy')
      db_template = @test_data["ComponentDefinition"]["Valid"]["PostgresqlSnapshot"]["Configuration"]["Database"]
      expected_template = @test_data["TestResult"]["PostgresqlSnapshot"]

      _process_db_instances(
        template: template,
        db_instance_definitions: { "Database" => db_template },
        db_parameter_group: {},
        snapshot_identifier: nil,
        security_group_ids: ["sg123"],
        component_name: "DBInstance"
      )

      expect(template).to eq expected_template
      _validate_db_login template, expected_template
    end

    it 'returns db instances template for PostgresqlRestore' do
      template = { 'Resources' => {}, 'Outputs' => {} }
      allow(Context).to receive_message_chain('kms.secrets_key_arn').and_return('kms-dummy')
      db_template = @test_data["ComponentDefinition"]["Valid"]["PostgresqlRestore"]["Configuration"]["Database"]
      expected_template = @test_data["TestResult"]["PostgresqlRestore"]

      _process_db_instances(
        template: template,
        db_instance_definitions: { "Database" => db_template },
        db_parameter_group: {},
        snapshot_identifier: "rds:aphodx67ufe3cm-2016-07-06-16-46",
        security_group_ids: ["sg123"],
        component_name: "DBInstance"
      )

      expect(template).to eq expected_template
      _validate_db_login template, expected_template
    end

    it 'returns db instances template for Postgresql Override' do
      template = { 'Resources' => {}, 'Outputs' => {} }
      allow(Context).to receive_message_chain('kms.secrets_key_arn').and_return('kms-dummy')
      db_template = @test_data["ComponentDefinition"]["Valid"]["PostgresqlOverride"]["Configuration"]["Database"]
      expected_template = @test_data["TestResult"]["PostgresqlOverride"]

      _process_db_instances(
        template: template,
        db_instance_definitions: { "Database" => db_template },
        db_parameter_group: {},
        snapshot_identifier: nil,
        security_group_ids: ["sg123"],
        component_name: "DBInstance"
      )

      expect(template).to eq expected_template
      _validate_db_login template, expected_template
    end
  end
end # RSpec.describe
