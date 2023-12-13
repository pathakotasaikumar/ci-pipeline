$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws")

require 'aws_rds'
require 'yaml'

RSpec.describe AwsRds do
  before(:context) do
    @test_data = YAML.load(
      File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"),
      permitted_classes: ['IpSecurityRule', 'IpPort']
    )["UnitTest"]
  end

  context '.initialize' do
    it 'initialises successfully for component definition with SingleDB / DBCluster ' do
      expect {
        @test_data["ComponentDefinition"]["Valid"].each do |key, value|
          AwsRds.new(@test_data["ComponentName"], value)
        end
      }.not_to raise_error
    end

    it 'raises exception if resource name is invalid' do
      expect {
        AwsRds.new(
          @test_data["ComponentName"],
          @test_data["ComponentDefinition"]["Invalid"]["ResourceName"]
        )
      }.to raise_error(RuntimeError, /Invalid resource name/)
    end

    it 'raises exception if multiple db clusters are defined' do
      expect {
        AwsRds.new(
          @test_data["ComponentName"],
          @test_data["ComponentDefinition"]["Invalid"]["MultipleDbCluster"]
        )
      }.to raise_error(RuntimeError, /does not support multiple/)
    end

    it 'raises exception if multiple option groups are defined' do
      expect {
        AwsRds.new(
          @test_data["ComponentName"],
          @test_data["ComponentDefinition"]["Invalid"]["MultipleOptionGroup"]
        )
      }.to raise_error(RuntimeError, /does not support multiple/)
    end

    it 'raises exception if multiple parameter groups are defined' do
      expect {
        AwsRds.new(
          @test_data["ComponentName"],
          @test_data["ComponentDefinition"]["Invalid"]["MultipleParamGroup"]
        )
      }.to raise_error(RuntimeError, /does not support multiple/)
    end

    it 'raises exception if multiple subnet are defined' do
      expect {
        AwsRds.new(
          @test_data["ComponentName"],
          @test_data["ComponentDefinition"]["Invalid"]["MultipleDBSubnet"]
        )
      }.to raise_error(RuntimeError, /does not support multiple/)
    end

    it 'raises exception if multiple db cluster param are defined' do
      expect {
        AwsRds.new(
          @test_data["ComponentName"],
          @test_data["ComponentDefinition"]["Invalid"]["MultipleDBClusterParam"]
        )
      }.to raise_error(RuntimeError, /does not support multiple/)
    end

    it 'raises exception if resource type is not defined' do
      expect {
        AwsRds.new(
          @test_data["ComponentName"],
          @test_data["ComponentDefinition"]["Invalid"]["UndefinedResourceType"]
        )
      }.to raise_error(RuntimeError, /specify a type for resource/)
    end

    it 'raises exception if resource type is unsupported' do
      expect {
        AwsRds.new(
          @test_data["ComponentName"],
          @test_data["ComponentDefinition"]["Invalid"]["UnsupportedResourceType"]
        )
      }.to raise_error(RuntimeError, /Resource type ([a-zA-Z:"]*) is not supported by this component/)
    end

    it 'raises exception if source snapshot is not a hash' do
      expect {
        AwsRds.new(
          @test_data["ComponentName"],
          @test_data["ComponentDefinition"]["Invalid"]["NonHashSourceSnapshot"]
        )
      }.to raise_error(RuntimeError, /Pipeline::SourceSnapshot must be an Hash/)
    end
  end

  context '.security_items' do
    it 'returns security group details for component definition with SingleDB / DBCluster' do
      @test_data["ComponentDefinition"]["Valid"].each do |key, value|
        aws_rds = AwsRds.new(@test_data["ComponentName"], value)
        expect(aws_rds.security_items).to eql @test_data["TestResult"]["SecurityItems"]
      end
    end
  end

  context '.security_rules' do
    it 'raises exception if Inbound Rules source is undefined' do
      expect {
        aws_rds = AwsRds.new(
          @test_data["ComponentName"],
          @test_data["ComponentDefinition"]["Invalid"]["UndefinedIrSource"]
        )
        aws_rds.security_rules
      }.to raise_error(RuntimeError, /Must specify a security rule source/)
    end

    it 'returns security rules for component definition with SingleDB' do
      aws_rds = AwsRds.new(
        @test_data["ComponentName"],
        @test_data["ComponentDefinition"]["Valid"]["SingleDb"]
      )
      expect(aws_rds.security_rules.to_yaml).to eql @test_data["TestResult"]["SecurityRules"].to_yaml
    end
  end

  context '.deploy' do
    it 'success' do
      @test_data['ComponentDefinition']['Valid'].each do |key, value|
        # deep clone
        value = Marshal.load(Marshal.dump(value))
        aws_rds = AwsRds.new(@test_data['ComponentName'], value)

        allow(PipelineMetadataService).to receive(:load_metadata).and_return('1')

        allow(aws_rds).to receive(:_process_db_instance_snapshot)
        allow(Defaults).to receive(:component_stack_name).and_return('dummy-stack-name')
        allow(Defaults).to receive(:get_tags).and_return([])
        allow(aws_rds).to receive(:_build_template).and_return({ 'Resources' => {}, 'Outputs' => {} })
        allow(Context).to receive_message_chain('component.set_variables')

        allow(aws_rds).to receive(:_process_template_parameters)
        allow(aws_rds).to receive(:_upload_log_artefacts)

        allow(aws_rds).to receive(:_process_db_cluster_snapshot)
        allow(aws_rds).to receive(:_process_db_instance_snapshot)

        allow(aws_rds).to receive(:_process_target_db_cluster_snapshot)
        allow(aws_rds).to receive(:_process_target_db_instance_snapshot)
        allow(aws_rds).to receive(:_process_settings_password).and_return('1')

        allow(AwsHelper).to receive(:cfn_create_stack)
        allow(AwsHelper).to receive(:s3_download_objects)
        allow(Context).to receive_message_chain('component.variable')
        allow(AwsHelper).to receive(:rds_wait_for_status_available)
        allow(AwsHelper).to receive(:rds_enable_copy_tags_to_snapshot)
        allow(AwsHelper).to receive(:rds_enable_cloudwatch_logs_export)

        allow(Context).to receive_message_chain('s3.artefact_bucket_name')
        allow(Defaults).to receive(:log_upload_path)

        allow(Defaults).to receive(:ad_dns_zone?)
        expect { aws_rds.deploy }.not_to raise_error
      end
    end

    it 'fails with ActionError' do
      @test_data['ComponentDefinition']['Valid'].each do |key, value|
        # deep clone
        value = Marshal.load(Marshal.dump(value))
        aws_rds = AwsRds.new(@test_data['ComponentName'], value)

        allow(aws_rds).to receive(:_process_db_cluster_snapshot)
        allow(aws_rds).to receive(:_process_db_instance_snapshot)
        allow(aws_rds).to receive(:_process_target_db_cluster_snapshot)
        allow(aws_rds).to receive(:_process_target_db_instance_snapshot)
        allow(Defaults).to receive(:component_stack_name).and_return('dummy-stack-name')
        allow(Defaults).to receive(:get_tags).and_return([])

        allow(aws_rds).to receive(:_build_template).and_return({ 'Resources' => {}, 'Outputs' => {} })
        allow(Context).to receive_message_chain('component.set_variables')

        allow(aws_rds).to receive(:_process_template_parameters)
        allow(aws_rds).to receive(:_upload_log_artefacts)
        allow(aws_rds).to receive(:_process_settings_password).and_return('1')

        allow(AwsHelper).to receive(:cfn_create_stack).and_raise(RuntimeError)
        allow(AwsHelper).to receive(:s3_download_objects)
        allow(Context).to receive_message_chain('s3.artefact_bucket_name')
        allow(Defaults).to receive(:log_upload_path)

        expect { aws_rds.deploy }.to raise_exception RuntimeError
      end
    end

    it 'fails with "Failed to deploy DNS records"' do
      @test_data['ComponentDefinition']['Valid'].each do |key, value|
        # deep clone
        value = Marshal.load(Marshal.dump(value))
        aws_rds = AwsRds.new(@test_data['ComponentName'], value)

        allow(PipelineMetadataService).to receive(:load_metadata).and_return('1')

        allow(aws_rds).to receive(:_process_db_cluster_snapshot)
        allow(aws_rds).to receive(:_process_db_instance_snapshot)
        allow(aws_rds).to receive(:_process_target_db_cluster_snapshot)
        allow(aws_rds).to receive(:_process_target_db_instance_snapshot)
        allow(Defaults).to receive(:component_stack_name).and_return('dummy-stack-name')
        allow(Defaults).to receive(:get_tags).and_return([])

        allow(aws_rds).to receive(:_build_template).and_return({ 'Resources' => {}, 'Outputs' => {} })
        allow(Context).to receive_message_chain('component.set_variables')

        allow(aws_rds).to receive(:_process_template_parameters)
        allow(aws_rds).to receive(:_upload_log_artefacts)
        allow(aws_rds).to receive(:_process_settings_password).and_return('1')

        allow(AwsHelper).to receive(:cfn_create_stack)
        allow(AwsHelper).to receive(:s3_download_objects)
        allow(Context).to receive_message_chain('component.variable')
        allow(AwsHelper).to receive(:rds_wait_for_status_available)
        allow(AwsHelper).to receive(:rds_enable_copy_tags_to_snapshot)
        allow(Context).to receive_message_chain('s3.artefact_bucket_name')
        allow(Defaults).to receive(:log_upload_path)

        allow(Defaults).to receive(:ad_dns_zone?).and_return(true)
        allow(aws_rds).to receive(:deploy_rds_ad_dns_records).and_raise(RuntimeError)
        expect { aws_rds.deploy }.to raise_exception(/Failed to deploy DNS records/)
      end
    end

    it 'fails with Invalid arguments' do
      aws_rds = AwsRds.new(@test_data['ComponentName'], @test_data["ComponentDefinition"]["Invalid"]["InvalidSnapshotArgument"])

      allow(aws_rds).to receive(:_process_db_cluster_snapshot)
      allow(aws_rds).to receive(:_process_db_instance_snapshot)
      allow(Defaults).to receive(:component_stack_name).and_return('dummy-stack-name')
      allow(Defaults).to receive(:get_tags).and_return([])

      allow(aws_rds).to receive(:_build_template).and_return({ 'Resources' => {}, 'Outputs' => {} })
      allow(Context).to receive_message_chain('component.set_variables')

      allow(aws_rds).to receive(:_process_template_parameters)
      allow(aws_rds).to receive(:_upload_log_artefacts)

      allow(AwsHelper).to receive(:cfn_create_stack)
      allow(AwsHelper).to receive(:s3_download_objects)
      allow(Context).to receive_message_chain('s3.artefact_bucket_name')
      allow(Defaults).to receive(:log_upload_path)

      allow(Defaults).to receive(:ad_dns_zone?).and_return(true)
      allow(aws_rds).to receive(:deploy_rds_ad_dns_records).and_raise(RuntimeError)
      expect { aws_rds.deploy }.to raise_exception(/Error: Invalid arguments are passed for Pipeline::SourceSnapshot properties/)
    end

    it 'catches create stack action error' do
      aws_rds = AwsRds.new(@test_data['ComponentName'], @test_data["ComponentDefinition"]["Valid"]["SingleDb"])

      allow(aws_rds).to receive(:_process_db_instance_snapshot)
      allow(Defaults).to receive(:component_stack_name).and_return('dummy-stack-name')
      allow(Defaults).to receive(:get_tags).and_return([])

      allow(aws_rds).to receive(:_build_template).and_return({ 'Resources' => {}, 'Outputs' => {} })
      allow(Context).to receive_message_chain('component.set_variables')

      allow(aws_rds).to receive(:_process_template_parameters)
      allow(aws_rds).to receive(:_upload_log_artefacts)

      allow(AwsHelper).to receive(:cfn_create_stack).and_raise(ActionError)
      allow(AwsHelper).to receive(:s3_download_objects)
      allow(Context).to receive_message_chain('s3.artefact_bucket_name')
      allow(Defaults).to receive(:log_upload_path)

      expect { aws_rds.deploy }.to raise_exception(/Failed to create RDS stack/)
    end
  end

  context '.release' do
    it 'updates dns record' do
      @test_data['ComponentDefinition']['Valid'].each do |key, value|
        aws_rds = AwsRds.new(@test_data['ComponentName'], value)
        allow(Util::Nsupdate).to receive(:create_dns_record)
        allow(Defaults).to receive_messages(:release_dns_name => 2)
        allow(Context).to receive_message_chain('component.variable').and_return('dns-2')

        expect { aws_rds.release }.not_to raise_error
      end
    end
  end

  context '.teardown' do
    it 'deletes stack and dns record and takes last backup if prod' do
      # AwsHelper = double (AwsHelper)

      allow(AwsHelper).to receive(:s3_get_object)
      allow(AwsHelper).to receive(:cfn_delete_stack)
      allow(AwsHelper).to receive(:rds_delete_db_instance_snapshots).and_return(nil)
      allow(AwsHelper).to receive(:rds_delete_db_cluster_snapshots).and_return(nil)
      @test_data['ComponentDefinition']['Valid'].each do |key, value|
        aws_rds = AwsRds.new(@test_data['ComponentName'], value)
        allow(aws_rds).to receive(:_clean_rds_ad_deployment_dns_record).with(no_args)
        allow(aws_rds).to receive(:_clean_rds_ad_release_dns_record).with(no_args)
        allow(aws_rds).to receive(:_process_db_instance_snapshot)
        allow(aws_rds).to receive(:_process_db_cluster_snapshot)
        allow(Util::Nsupdate).to receive_messages(:delete_dns_record => 1)

        # We take a final snapshot before tearing down PROD
        allow(Defaults).to receive(:sections).and_return({
          :ams => "AMS01",
          :qda => "C031",
          :as => "01",
          :ase => "PROD",
          :env => "PROD",
          :asbp_type => "qda",
          :type => "aws/rds-aurora-postgresql",
        })
        expect { aws_rds.send(:_take_last_backup) }.not_to raise_error
        expect { AwsHelper.send(:rds_delete_db_cluster_snapshots, ["test123"]) }.not_to raise_error

        allow(Defaults).to receive(:sections).and_return({
          :ams => "AMS01",
          :qda => "C031",
          :as => "01",
          :ase => "PROD",
          :env => "PROD",
          :asbp_type => "qda",
          :type => "aws/rds",
        })
        expect { aws_rds.send(:_take_last_backup) }.not_to raise_error
        AwsHelper.rds_delete_db_instance_snapshots(["test123"])
        AwsHelper.rds_delete_db_cluster_snapshots(["test123"])

        allow(Defaults).to receive(:snapshot_identifier)
        allow(Defaults).to receive(:get_tags).and_return([])

        expect { aws_rds.teardown }.not_to raise_error
      end
    end

    it 'raises exception on last backup' do
      aws_rds = AwsRds.new(@test_data["ComponentName"], @test_data["ComponentDefinition"]["Valid"]["SingleDb"])

      allow(Defaults).to receive(:sections).and_return({
        :env => "PROD",
      })
      # Should expect it to fail from having no valid section defaults which does an upcase
      expect { aws_rds.send(:_take_last_backup) }.to raise_error(RuntimeError)
    end

    it 'fails with exception' do
      allow(AwsHelper).to receive(:s3_get_object)
      allow(AwsHelper).to receive(:cfn_delete_stack).and_raise

      @test_data['ComponentDefinition']['Valid'].each do |key, value|
        aws_rds = AwsRds.new(@test_data['ComponentName'], value)
        allow(aws_rds).to receive(:teardown).and_raise
        expect { AwsHelper.send(:cfn_delete_stack, "test123") }.to raise_exception(RuntimeError)
        expect { aws_rds.teardown }.to raise_exception(RuntimeError)
      end
    end
  end

  context '._build_template', :skip => true do # needs to be seperately test for aurora, oracle,postgre, sql server, mysql
    it 'returns resources and outputs' do
      aws_rds = AwsRds.new(@test_data["ComponentName"], @test_data["ComponentDefinition"]["Valid"]["SingleDb"])

      allow(aws_rds).to receive_messages(:_process_db_subnet_group => 1,)
      allow(Context).to receive_message_chain("component_security.sg_id")

      expect(aws_rds._build_template).to eq({})
    end
  end

  context '._process_db_subnet_group', :skip => true do # test seperately in builder
    it 'returns db subnet group template' do
      aws_rds = AwsRds.new(@test_data["ComponentName"], @test_data["ComponentDefinition"]["Valid"]["SingleDb"])
      template = { 'Resources' => {}, 'Outputs' => {} }
      environmentContext = double(EnvironmentContext)
      allow(Context).to receive(:environment).and_return(environmentContext)
      allow(environmentContext).to receive(:variable).and_return("unit-test-subnet1")
      aws_rds._process_db_subnet_group(template: template, db_subnet_group: { "DBSubnetGroup" => {} })
      expect(template).to eq(@test_data["TestResult"]["_process_db_subnet_group"])
    end
  end

  context '._process_db_cluster', :skip => true do # test seperately in builder
    it 'returns db cluster template' do
      aws_rds = AwsRds.new(@test_data["ComponentName"], @test_data["ComponentDefinition"]["Valid"]["SingleDb"])
      template = { 'Resources' => {}, 'Outputs' => {} }
      db_cluster = { "DatabaseCluster1" => @test_data["ComponentDefinition"]["Valid"]["DBClusterMinimal"]["Configuration"]["DatabaseCluster1"] }
      asirContext = double(AsirContext)
      componentSecurityContext = double(ComponentSecurityContext)

      environmentContext = double(EnvironmentContext)

      aws_rds._process_db_cluster(
        template: template,
        db_cluster_definition: db_cluster,
        security_group_ids: ["sg-4eb21f2a", "sg-4eb21f2b"]
      )
      expect(template).to eq @test_data["TestResult"]["_process_db_cluster"]["Minimal"]

      template = { 'Resources' => {}, 'Outputs' => {} }
      db_cluster = { "DatabaseCluster1" => @test_data["ComponentDefinition"]["Valid"]["DBClusterOverloaded"]["Configuration"]["DatabaseCluster1"] }

      aws_rds._process_db_cluster(
        template: template,
        db_cluster_definition: db_cluster,
        security_group_ids: ["sg-4eb21f2a", "sg-4eb21f2b"]
      )
      expect(template).to eq @test_data["TestResult"]["_process_db_cluster"]["Overloaded"]
    end
  end

  context '._process_db_instances', :skip => true do # needs to be seperately test for aurora, oracle,postgre, sql server, mysql
    it 'returns db instances template for SingleDb' do
      aws_rds = AwsRds.new(@test_data["ComponentName"], @test_data["ComponentDefinition"]["Valid"]["SingleDb"])
      # allow(aws_rds).to receive(:_get_snapshot_id) .and_return("snapshot-1234")
      allow(Context).to receive_message_chain("component_security.sg_id").and_return(["sg123"])

      template = { 'Resources' => {}, 'Outputs' => {} }
      aws_rds._process_db_instances(template: template,
                                    db_instance_definitions: { "Database" => @test_data["ComponentDefinition"]["Valid"]["SingleDb"]["Configuration"]["Database"] },
                                    db_cluster_name: nil,
                                    security_group_ids: ["sg123"])
      expect(template).to eq @test_data["TestResult"]["_process_db_instances"]["SingleDb-ExistingSnapShot"]

      template = { 'Resources' => {}, 'Outputs' => {} }
      aws_rds._process_db_instances(template: template,
                                    db_instance_definitions: { "Database" => @test_data["ComponentDefinition"]["Valid"]["SingleDbMinimalConfig"]["Configuration"]["Database"] },
                                    db_cluster_name: nil,
                                    security_group_ids: ["sg123"])
      expect(template).to eq @test_data["TestResult"]["_process_db_instances"]["SingleDbMinimalConfig"]

      template = { 'Resources' => {}, 'Outputs' => {} }
      aws_rds._process_db_instances(template: template,
                                    db_instance_definitions: { "Database" => @test_data["ComponentDefinition"]["Valid"]["SingleDbOverloadedConfig"]["Configuration"]["Database"] },
                                    db_cluster_name: nil,
                                    security_group_ids: ["sg123"])
      expect(template).to eq @test_data["TestResult"]["_process_db_instances"]["SingleDbOverloadedConfig"]
    end

    it 'returns db instances template for DBCluster', :skip => true do
      aws_rds = AwsRds.new(@test_data["ComponentName"], @test_data["ComponentDefinition"]["Valid"]["DBClusterMinimal"])
      # allow(aws_rds).to receive(:_get_snapshot_id) .and_return(nil)
      allow(GeneratePassword).to receive(:generate).and_return("#DRsRX|eDnzb^4Hs")
      template = { 'Resources' => {}, 'Outputs' => {} }
      db_instances = {
        "Database1" => @test_data["ComponentDefinition"]["Valid"]["DBClusterMinimal"]["Configuration"]["Database1"],
        "Database2" => @test_data["ComponentDefinition"]["Valid"]["DBClusterMinimal"]["Configuration"]["Database2"]
      }
      allow(Context).to receive_message_chain("component_security.sg_id").and_return(["sg123"])
      aws_rds._process_db_instances(
        template: template,
        db_instance_definitions: db_instances,
        db_cluster_name: "DatabaseCluster1",
        security_group_ids: ["sg123"]
      )
      expect(template).to eq @test_data["TestResult"]["_process_db_instances"]["ClusterDb-OptionGroup"]
    end
  end

  context '._process_template_parameters' do
    it 'can process template parameters' do
      component_name = @test_data["ComponentName"]
      instance_name = "Database"

      allow(Context).to receive_message_chain('environment.persist_override')

      allow(Context).to receive_message_chain('component.variable')
        .with(component_name, instance_name + 'MasterUsername', :undef)
        .and_return("root")

      allow(Context).to receive_message_chain('component.variable')
        .with(component_name, instance_name + 'MasterUserPassword', :undef)
        .and_return("pass")

      aws_rds = AwsRds.new(component_name, @test_data["ComponentDefinition"]["Valid"]["SingleDb"])

      aws_rds.send(:_process_template_parameters)
    end

    it 'raises err with nil params parameters' do
      component_name = @test_data["ComponentName"]
      instance_name = "Database"

      test_results = [
        [nil, nil],
        [nil, 'pass'],
        ['root', nil],

        ['', ''],
        ['', 'pass'],
        ['root', ''],

        [:undef, :undef],
        [:undef, 'pass'],
        ['root', :undef]
      ]

      test_results.each do |results|
        Log.debug("_process_template_parameters: testing with [#{results}]")

        allow(Context).to receive_message_chain('environment.persist_override')
        allow(Context).to receive_message_chain('component.variable')
          .with(component_name, instance_name + 'MasterUsername', '')
          .and_return(results[0])

        allow(Context).to receive_message_chain('component.variable')
          .with(component_name, instance_name + 'MasterUserPassword', '')
          .and_return(results[1])

        aws_rds = AwsRds.new(component_name, @test_data["ComponentDefinition"]["Valid"]["SingleDb"])
        aws_rds.instance_variable_set(:@template, { 'Parameters' => {
          instance_name + 'MasterUsername' => {},
          instance_name + 'MasterUserPassword' => {}
        } })

        expect { aws_rds.send(:_process_template_parameters) }.to raise_error(/Context variable (.+) is undefined, nil or empty/)
      end
    end

    context '_load_snapshot_tags' do
      it 'return default tags' do
        component_name = @test_data["ComponentName"]
        aws_rds = AwsRds.new(component_name, @test_data['LoadSnapshotTagsTest']['ValidSourceSnapshot'])
        allow(PipelineMetadataService).to receive(:load_metadata).and_return('1')
        expect { aws_rds.send :_load_snapshot_tags }.not_to raise_exception
        expect(aws_rds.send :_load_snapshot_tags).to eq({ :ase => "STG", :branch => "master", :component => "Test-Component", :resource => "Database", :build => "1" })
      end
      it 'test prod env tags' do
        component_name = @test_data["ComponentName"]
        aws_rds = AwsRds.new(component_name, @test_data['LoadSnapshotTagsTest']['ValidPRODSourceSnapshot'])
        allow(PipelineMetadataService).to receive(:load_metadata).and_return('2')
        expect { aws_rds.send :_load_snapshot_tags }.not_to raise_exception
        expect(aws_rds.send :_load_snapshot_tags).to eq({ :ase => "PROD", :branch => "master", :component => "Test-Component", :resource => "Database", :build => "2" })
      end
    end

    context '_validate_and_modify_rds_password' do
      it 'Raise error if plain text password is defined' do
        component_name = @test_data["ComponentName"]

        aws_rds = AwsRds.new(component_name, @test_data["ComponentDefinition"]["Validate_Rds_definition"]["PlainText"])

        expect { aws_rds.send(:_validate_and_modify_rds_password) }.to raise_exception(/DB Password can't be set as plaintext value.Please use the QCP Secret Manager to encrypt the password and reference it in your YAML./)
      end

      it 'successfully parse the rds master password' do
        component_name = @test_data["ComponentName"]

        aws_rds = AwsRds.new(component_name, @test_data["ComponentDefinition"]["Validate_Rds_definition"]["SingleDb"])

        expect(aws_rds).to receive(:_process_db_password).once
        expect { aws_rds.send(:_validate_and_modify_rds_password) }.not_to raise_exception
      end

      it 'successfully parse the rds master password for cluster' do
        component_name = @test_data["ComponentName"]

        aws_rds = AwsRds.new(component_name, @test_data["ComponentDefinition"]["Validate_Rds_definition"]["DBClusterMinimal"])

        expect(aws_rds).to receive(:_process_db_password).once
        expect { aws_rds.send(:_validate_and_modify_rds_password) }.not_to raise_exception
      end
    end

    context '_reset_rds_database_password' do
      it 'successfully parse the rds master password' do
        component_name = @test_data["ComponentName"]

        aws_rds = AwsRds.new(component_name, @test_data["ComponentDefinition"]["_reset_rds_database_password"]["SingleDb"])

        allow(Context).to receive_message_chain('component.variable')
        allow(AwsHelper).to receive(:rds_reset_password)
        allow(Context).to receive_message_chain('component.set_variables')

        expect { aws_rds.send(:_reset_rds_database_password) }.not_to raise_exception
      end

      it 'successfully parse the rds master password for cluster' do
        component_name = @test_data["ComponentName"]

        aws_rds = AwsRds.new(component_name, @test_data["ComponentDefinition"]["_reset_rds_database_password"]["DBClusterMinimal"])

        allow(Context).to receive_message_chain('component.variable')
        allow(AwsHelper).to receive(:rds_reset_password)
        allow(Context).to receive_message_chain('component.set_variables')

        expect { aws_rds.send(:_reset_rds_database_password) }.not_to raise_exception
      end

      it 'fails with Failed to reset' do
        component_name = @test_data["ComponentName"]

        aws_rds = AwsRds.new(component_name, @test_data["ComponentDefinition"]["_reset_rds_database_password"]["DBClusterMinimal"])

        allow(Context).to receive_message_chain('component.variable')
        allow(AwsHelper).to receive(:rds_reset_password)
        allow(Context).to receive_message_chain('component.set_variables').and_raise(ActionError)
        expect { aws_rds.send(:_reset_rds_database_password) }.to raise_error /Failed to reset the RDS Database password/
      end
    end
  end
end # RSpec.describe
