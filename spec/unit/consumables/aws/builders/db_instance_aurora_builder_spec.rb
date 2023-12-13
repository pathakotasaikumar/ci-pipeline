$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws")
require 'builders/db_instance_aurora_builder'
require 'util/generate_password'

RSpec.describe DbInstanceAuroraBuilder do
  include DbInstanceAuroraBuilder

  before(:context) do
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))["UnitTest"]
  end

  context '._process_db_parameter_group' do
    it 'aurora: returns value from db_parameter_group' do
      resource = {
        "Properties" => {}
      }
      db_parameter_group = {
        "Group1" => {}
      }

      _process_db_parameter_group(
        resource: resource,
        db_parameter_group: db_parameter_group
      )

      expect(resource["Properties"]["DBParameterGroupName"]).to eq({
        "Ref" => "Group1"
      })
    end

    it 'aurora: returns nothing with empty db_parameter_group' do
      resource = {
        "Properties" => {}
      }
      db_parameter_group = {}

      _process_db_parameter_group(
        resource: resource,
        db_parameter_group: db_parameter_group
      )

      expect(resource["Properties"]["DBParameterGroupName"]).to eq(nil)
    end

    it 'aurora: returns nothing with empty db_parameter_group' do
      resource = {
        "Properties" => {}
      }
      db_parameter_group = {}

      _process_db_parameter_group(
        resource: resource,
        db_parameter_group: db_parameter_group
      )

      expect(resource["Properties"]["DBParameterGroupName"]).to eq(nil)
    end

    it 'aurora: leave DBParameterGroupName alone' do
      resource = {
        "Properties" => {
          "DBParameterGroupName" => "default.aurora-postgresql10"
        }
      }
      db_parameter_group = {
        "Group1" => {}
      }

      _process_db_parameter_group(
        resource: resource,
        db_parameter_group: db_parameter_group
      )

      expect(resource["Properties"]["DBParameterGroupName"]).to eq("default.aurora-postgresql10")
    end
  end

  context '_process_db_instances' do
    it 'returns db Instance template for AuroraMinimal' do
      template = { 'Resources' => {}, 'Outputs' => {} }
      @db_cluster = { "Cluster" => @test_data["AuroraMinimal"]["Configuration"]["Cluster"] }

      _process_db_instances(
        template: template,
        db_instance_definitions: {
          "MyDBInstance1" => @test_data["AuroraMinimal"]["Configuration"]["MyDBInstance1"],
          "MyDBInstance2" => @test_data["AuroraMinimal"]["Configuration"]["MyDBInstance2"],
          "MyDBInstance3" => @test_data["AuroraMinimal"]["Configuration"]["MyDBInstance3"]
        },
        db_parameter_group: {},
        db_cluster_name: @db_cluster.keys[0],
        component_name: "DBInstance"
      )

      expect(template).to eq @test_data["TestResult"]["_process_db_instances"]["AuroraMinimal"]

      # emptyhash = {}
      # expect(YAML.dump(template)).to eq emptyhash
    end

    it 'returns 5th gen db Instance template for old gen' do
      template = { 'Resources' => {}, 'Outputs' => {} }
      @db_cluster = { "Cluster" => @test_data["AuroraOldGen"]["Configuration"]["Cluster"] }

      _process_db_instances(
        template: template,
        db_instance_definitions: {
          "MyDBInstance1" => @test_data["AuroraOldGen"]["Configuration"]["MyDBInstance1"],
          "MyDBInstance2" => @test_data["AuroraOldGen"]["Configuration"]["MyDBInstance2"],
          "MyDBInstance3" => @test_data["AuroraOldGen"]["Configuration"]["MyDBInstance3"],
          "MyDBInstance4" => @test_data["AuroraOldGen"]["Configuration"]["MyDBInstance4"]
        },
        db_parameter_group: {},
        db_cluster_name: @db_cluster.keys[0],
        component_name: "DBInstance"
      )

      expect(template).to eq @test_data["TestResult"]["_process_db_instances"]["AuroraOldGen"]

      # emptyhash = {}
      # expect(YAML.dump(template)).to eq emptyhash
    end

  end
end # RSpec.describe
