$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws")
require 'builders/db_instance_sqlserver_builder'
require 'util/generate_password'
require_relative 'db_instance_spec_helper'

RSpec.describe DbInstanceSqlserverBuilder do
  include DbInstanceSqlserverBuilder
  include DbInstanceSpecHelper

  before(:context) do
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))["UnitTest"]
  end

  context 'AwsRdsSqlserver._process_db_instances' do
    it 'returns db instances template for SqlserverMinimal' do
      template = { 'Resources' => {}, 'Outputs' => {} }

      db_template = @test_data["ComponentDefinition"]["Valid"]["SqlserverMinimal"]["Configuration"]["Database"]
      expected_template = @test_data["TestResult"]["SqlserverMinimal"]

      allow(Context)
        .to receive_message_chain('kms.secrets_key_arn')
        .and_return('kms-dummy')
      _process_db_instances(template: template,
                            db_instance_definitions: { "Database" => db_template },
                            db_parameter_group: {},
                            db_option_group: {},
                            security_group_ids: ["sg123"],
                            component_name: "DBInstance")

      expect(template).to eq expected_template
      _validate_db_login template, expected_template
    end

    it 'returns db instances template for SqlserverMinimal - EX' do
      template = { 'Resources' => {}, 'Outputs' => {} }

      db_template = @test_data["ComponentDefinition"]["Valid"]["SqlserverMinimalEX"]["Configuration"]["Database"]
      expected_template = @test_data["TestResult"]["SqlserverMinimalEX"]

      allow(Context).to receive_message_chain('kms.secrets_key_arn').and_return('kms-dummy')
      _process_db_instances(
        template: template,
        db_instance_definitions: { "Database" => db_template },
        db_parameter_group: {},
        db_option_group: {},
        security_group_ids: ["sg123"],
        component_name: "DBInstance"
      )

      expect(template).to eq expected_template
      _validate_db_login template, expected_template
    end

    it 'returns db instances template for SqlserverMinimal - EE' do
      template = { 'Resources' => {}, 'Outputs' => {} }

      db_template = @test_data["ComponentDefinition"]["Valid"]["SqlserverMinimalEE"]["Configuration"]["Database"]
      expected_template = @test_data["TestResult"]["SqlserverMinimalEE"]

      allow(Context).to receive_message_chain('kms.secrets_key_arn').and_return('kms-dummy')
      _process_db_instances(
        template: template,
        db_instance_definitions: { "Database" => db_template },
        db_parameter_group: {},
        db_option_group: {},
        security_group_ids: ["sg123"],
        component_name: "DBInstance"
      )

      expect(template).to eq expected_template
      _validate_db_login template, expected_template
    end

    it 'returns db instances template for SqlserverSnap' do
      template = { 'Resources' => {}, 'Outputs' => {} }

      db_template = @test_data["ComponentDefinition"]["Valid"]["SqlserverSnap"]["Configuration"]["Database"]
      expected_template = @test_data["TestResult"]["SqlserverSnap"]

      allow(Context).to receive_message_chain('kms.secrets_key_arn').and_return('kms-dummy')
      _process_db_instances(
        template: template,
        db_instance_definitions: { "Database" => db_template },
        db_parameter_group: {},
        db_option_group: {},
        snapshot_identifier: 'dummy-snap',
        security_group_ids: ["sg123"],
        component_name: "DBInstance"
      )

      expect(template).to eq expected_template
      _validate_db_login template, expected_template
    end

    it 'returns db instances template for SqlserverPersist' do
      template = { 'Resources' => {}, 'Outputs' => {} }
      allow(Context)
        .to receive_message_chain('kms.secrets_key_arn')
        .and_return('kms-dummy')

      db_template = @test_data["ComponentDefinition"]["Valid"]["SqlserverPersist"]["Configuration"]["Database"]
      expected_template = @test_data["TestResult"]["SqlserverPersist"]

      _process_db_instances(template: template,
                            db_instance_definitions: { "Database" => db_template },
                            db_parameter_group: {},
                            db_option_group: {},
                            security_group_ids: ["sg123"],
                            component_name: "DBInstance")

      expect(template).to eq expected_template
      _validate_db_login template, expected_template
    end

    it 'returns db instances template for SqlserverSEOverride' do
      template = { 'Resources' => {}, 'Outputs' => {} }
      allow(Context)
        .to receive_message_chain('kms.secrets_key_arn')
        .and_return('kms-dummy')

      db_template = @test_data["ComponentDefinition"]["Valid"]["SqlserverSEOverride"]["Configuration"]["Database"]
      expected_template = @test_data["TestResult"]["SqlserverSEOverride"]

      _process_db_instances(template: template,
                            db_instance_definitions: { "Database" => db_template },
                            db_parameter_group: {},
                            db_option_group: {},
                            security_group_ids: ["sg123"],
                            component_name: "DBInstance")
      expect(template).to eq expected_template

      expect(template).to eq expected_template
      _validate_db_login template, expected_template
    end

    it 'fails with Unsupported database engine' do
      template = { 'Resources' => {}, 'Outputs' => {} }

      db_template = @test_data["ComponentDefinition"]["Invalid"]["BadEngine"]["Configuration"]["Database"]
      allow(Context).to receive_message_chain('kms.secrets_key_arn').and_return('kms-dummy')

      expect {
        _process_db_instances(
          template: template,
          db_instance_definitions: { "Database" => db_template },
          db_parameter_group: {},
          db_option_group: {},
          security_group_ids: ["sg123"],
          component_name: "DBInstance"
        )
      }.to raise_exception /Unsupported database engine/
    end

    it 'returns db instances template for Timezone' do
      template = { 'Resources' => {}, 'Outputs' => {} }

      db_template = @test_data["ComponentDefinition"]["Valid"]["MSSQLrdsTimezone"]["Configuration"]["Database"]
      expected_template = @test_data["TestResult"]["MSSQLrdsTimezone"]

      allow(Context)
        .to receive_message_chain('kms.secrets_key_arn')
        .and_return('kms-dummy')
      _process_db_instances(template: template,
                            db_instance_definitions: { "Database" => db_template },
                            db_parameter_group: {},
                            db_option_group: {},
                            security_group_ids: ["sg123"],
                            component_name: "DBInstance")

      expect(template).to eq expected_template
      _validate_db_login template, expected_template
    end
        
  end
end # RSpec.describe
