$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws")
require 'builders/db_instance_mysql_builder'
require 'util/generate_password'
require_relative 'db_instance_spec_helper'

RSpec.describe DbInstanceMysqlBuilder do
  include DbInstanceMysqlBuilder
  include DbInstanceSpecHelper

  before(:context) do
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))["UnitTest"]
  end

  context 'AwsRdsMysql._process_db_instances' do
    it 'returns db instances template for MySQLSingleDb' do
      template = { 'Resources' => {}, 'Outputs' => {} }
      allow(Context).to receive_message_chain('kms.secrets_key_arn').and_return('kms-dummy')
      db_template = @test_data["ComponentDefinition"]["Valid"]["MySQLSingleDb"]["Configuration"]["Database"]
      expected_template = @test_data["TestResult"]["_process_db_instances"]["MySQLSingleDb"]

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

    it 'returns db instances template for MySQLSingleDbSnapshot' do
      template = { 'Resources' => {}, 'Outputs' => {} }
      allow(Context).to receive_message_chain('kms.secrets_key_arn').and_return('kms-dummy')
      db_template = @test_data["ComponentDefinition"]["Valid"]["MySQLSingleDbSnapshot"]["Configuration"]["Database"]
      expected_template = @test_data["TestResult"]["_process_db_instances"]["MySQLSingleDbSnapshot"]

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

    it 'builder returns db instances template for MySQLSingleReplica' do
      template = { 'Resources' => {}, 'Outputs' => {} }
      allow(Context).to receive_message_chain('kms.secrets_key_arn').and_return('kms-dummy')
      db_primary_template = @test_data["ComponentDefinition"]["Valid"]["MySQLSingleReplica"]["Configuration"]["MySQLPrimary"]
      db_replica_template = @test_data["ComponentDefinition"]["Valid"]["MySQLSingleReplica"]["Configuration"]["MySQLReplica1"]
      expected_template = @test_data["TestResult"]["_process_db_instances"]["MySQLSingleReplica"]

      _process_db_instances(
        template: template,
        db_instance_definitions: {
          "MySqlPrimary" => db_primary_template,
          "MySqlReplica1" => db_replica_template
        },
        db_parameter_group: {},
        db_option_group: {},
        snapshot_identifier: nil,
        security_group_ids: ["sg123"],
        component_name: "DBInstance"
      )

      expect(template).to eq expected_template
      _validate_db_login template, expected_template
    end

    it 'builder returns db instances template for Snaps' do
      template = { 'Resources' => {}, 'Outputs' => {} }
      allow(Context)
        .to receive_message_chain('kms.secrets_key_arn')
        .and_return('kms-dummy')
      _process_db_instances(
        template: template,
        db_instance_definitions: { "Snaps" => @test_data["ComponentDefinition"]["Variations"]["Snaps"] },
        db_parameter_group: {},
        db_option_group: {},
        snapshot_identifier: "variation2-db",
        security_group_ids: ["sg123"],
        component_name: "DBInstance"
      )
      expect(template).to eq @test_data["TestResult"]["_process_db_instances"]["Variations"]["Snaps"]
    end

    it 'builder returns db instances template for LatestSnap' do
      template = { 'Resources' => {}, 'Outputs' => {} }
      allow(Context)
        .to receive_message_chain('kms.secrets_key_arn')
        .and_return('kms-dummy')
      _process_db_instances(
        template: template,
        db_instance_definitions: { "LatestSnap" => @test_data["ComponentDefinition"]["Variations"]["LatestSnap"] },
        db_parameter_group: {},
        db_option_group: {},
        snapshot_identifier: "Mocked-Latest-Return",
        security_group_ids: ["sg123"],
        component_name: "DBInstance"
      )
      expect(template).to eq @test_data["TestResult"]["_process_db_instances"]["Variations"]["LatestSnap"]
    end

    it 'builder returns db instances template for OtherType' do
      template = { 'Resources' => {}, 'Outputs' => {} }
      allow(Context).to receive_message_chain('kms.secrets_key_arn')
        .and_return('kms-dummy')
      _process_db_instances(
        template: template,
        db_instance_definitions: {
          "OtherType" => @test_data["ComponentDefinition"]["Variations"]["OtherType"]
        },
        db_parameter_group: {},
        db_option_group: {},
        snapshot_identifier: nil,
        security_group_ids: ["sg123"],
        component_name: "DBInstance"
      )
      expect(template).to eq @test_data["TestResult"]["_process_db_instances"]["Variations"]["OtherType"]
    end
  end
end # RSpec.describe
