$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws")
require 'builders/db_cluster_aurora_builder'
require 'util/generate_password'
require_relative 'db_instance_spec_helper'

RSpec.describe DbClusterAuroraBuilder do
  include DbClusterAuroraBuilder
  include DbInstanceSpecHelper

  before(:context) do
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))["UnitTest"]
  end

  context '._process_db_cluster_parameter_group' do
    it 'aurora: returns values from db_cluster_parameters' do
      resource = {
        "Properties" => {}
      }
      db_cluster_parameters = {
        "Group1" => {}
      }

      _process_aurora_db_cluster_parameter_group(
        resource: resource,
        db_cluster_parameters: db_cluster_parameters
      )

      expect(resource["Properties"]["DBClusterParameterGroupName"]).to eq({
        "Ref" => "Group1"
      })
    end

    it 'aurora: does nothing on empty db_cluster_parameters' do
      resource = {
        "Properties" => {}
      }
      db_cluster_parameters = {}

      _process_aurora_db_cluster_parameter_group(
        resource: resource,
        db_cluster_parameters: db_cluster_parameters
      )

      expect(resource["Properties"]).to_not have_key(:DBClusterParameterGroupName)
    end

    it 'aurora: leave DBClusterParameterGroupName alone' do
      resource = {
        "Properties" => {
          "DBClusterParameterGroupName" => "default.aurora-postgresql10"
        }
      }
      db_cluster_parameters = {
        "Group1" => {}
      }

      _process_aurora_db_cluster_parameter_group(
        resource: resource,
        db_cluster_parameters: db_cluster_parameters
      )

      expect(resource["Properties"]["DBClusterParameterGroupName"]).to eq("default.aurora-postgresql10")
    end
  end

  context '_process_db_cluster' do
    it 'raises on missed KMS keys' do
      template = { 'Resources' => {}, 'Outputs' => {} }
      allow(Context).to receive_message_chain('kms.secrets_key_arn').and_return('kms-dummy')
      db_template = @test_data["ComponentDefinition"]["Valid"]["AuroraMinimal"]["Configuration"]["MyDBCluster"]
      expected_template = @test_data["TestResult"]["_process_db_cluster"]["AuroraMinimal"]

      allow(Context).to receive_message_chain('kms.secrets_key_arn').and_return(nil)

      expect {
        _process_db_cluster(
          template: template,
          db_cluster_definition: { "AuroraMinimal" => db_template },
          db_cluster_parameters: { 'DummyClusterParameterGroup' => {} },
          security_group_ids: ["sg123"],
          snapshot_identifier: nil,
          component_name: "AuroraMinimal"
        )
      }.to raise_error(/KMS key for application service/)
    end

    it 'returns db cluster template for AuroraMinimal' do
      template = { 'Resources' => {}, 'Outputs' => {} }
      # Switch to nonprod and non-qa for snapshot edge test
      allow(Defaults).to receive(:sections) .and_return({
        :env => 'nonprod',
        :ams => 'ams01',
        :qda => 'c031',
        :as => '99',
        :branch => 'master',
        :ase => 'prod',
        :build => '5'
      })
      allow(Context).to receive_message_chain('environment.qa?').and_return(false)
      allow(Context).to receive_message_chain('kms.secrets_key_arn').and_return('kms-dummy')
      db_template = @test_data["ComponentDefinition"]["Valid"]["AuroraMinimal"]["Configuration"]["MyDBCluster"]
      expected_template = @test_data["TestResult"]["_process_db_cluster"]["AuroraMinimal"]

      _process_db_cluster(
        template: template,
        db_cluster_definition: { "AuroraMinimal" => db_template },
        db_cluster_parameters: { 'DummyClusterParameterGroup' => {} },
        security_group_ids: ["sg123"],
        snapshot_identifier: nil,
        component_name: "AuroraMinimal"
      )

      expect(template).to eq expected_template
      _validate_db_login template, expected_template
    end

    it 'returns db cluster template for AuroraServerless' do
      template = { 'Resources' => {}, 'Outputs' => {} }
      allow(Context).to receive_message_chain('kms.secrets_key_arn').and_return('kms-dummy')
      db_template = @test_data["ComponentDefinition"]["Valid"]["AuroraServerless"]["Configuration"]["MyDBCluster"]
      expected_template = @test_data["TestResult"]["_process_db_cluster"]["AuroraServerless"]

      _process_db_cluster(
        template: template,
        db_cluster_definition: { "AuroraServerless" => db_template },
        db_cluster_parameters: { 'DummyClusterParameterGroup' => {} },
        security_group_ids: ["sg123"],
        snapshot_identifier: nil,
        component_name: "AuroraServerless"
      )

      expect(template).to eq expected_template
      _validate_db_login template, expected_template
    end

    it 'returns db cluster template for AuroraSnap' do
      template = { 'Resources' => {}, 'Outputs' => {} }
      allow(Context).to receive_message_chain('kms.secrets_key_arn').and_return('kms-dummy')
      db_template = @test_data["ComponentDefinition"]["Valid"]["AuroraSnap"]
      expected_template = @test_data["TestResult"]["_process_db_cluster"]["AuroraSnap"]

      _process_db_cluster(
        template: template,
        db_cluster_definition: { "AuroraSnap" => db_template },
        db_cluster_parameters: {},
        security_group_ids: ["sg123"],
        snapshot_identifier: 'dummy-snapshot',
        component_name: "AuroraSnap"
      )

      expect(template).to eq expected_template
      _validate_db_login template, expected_template
    end
  end
end # RSpec.describe
