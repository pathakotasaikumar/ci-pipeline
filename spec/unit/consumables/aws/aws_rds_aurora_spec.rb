$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws")
require 'aws_rds_aurora'

RSpec.describe AwsRdsAurora do
  before(:context) do
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/aws_rds_aurora_spec.yaml"))['UnitTest']
  end

  def _get_aurora_instance
    component_name = @test_data['ComponentName']
    valid_components = @test_data['ComponentDefinition']['Valid'].values

    AwsRdsAurora.new(component_name, valid_components.first)
  end

  context '.initialize' do
    it 'initialises without error' do
      @test_data['ComponentDefinition']['Valid'].values.each { |definition, index|
        expect { AwsRdsAurora.new(@test_data['ComponentName'], definition) }.not_to raise_error
      }
    end
  end

  context '._get_port_from_engine_name' do
    it 'returns value' do
      component = _get_aurora_instance

      expect(component.__send__(:_get_port_from_engine_name, 'aurora')).to eq('3306')
      expect(component.__send__(:_get_port_from_engine_name, 'aurora-mysql')).to eq('3306')

      expect {
        component.__send__(:_get_port_from_engine_name, 'aurora1')
      }.to raise_error(/Unknown engine name/)
    end
  end

  context '.security_items' do
    it 'returns security items' do
      aws_rds = AwsRdsAurora.new(
        @test_data['ComponentName'],
        @test_data['ComponentDefinition']['Valid']['AuroraFullBuild']
      )
      expect(aws_rds.security_items).to eq @test_data["TestResult"]["AuroraFullBuild"]['SecurityItems']
    end
  end

  context '.security_rules' do
    it 'returns security rules for component definition with full db' do
      aws_rds = AwsRdsAurora.new(
        @test_data['ComponentName'],
        @test_data['ComponentDefinition']['Valid']['AuroraFullBuild']
      )
      expect(aws_rds.security_rules.to_yaml).to eql @test_data["TestResult"]["AuroraFullBuild"]["SecurityRules"].to_yaml()
    end
  end

  context '.deploy' do
    it 'successfully executes' do
      aws_rds = AwsRdsAurora.new(@test_data['ComponentName'], @test_data['ComponentDefinition']['Valid']['AuroraFullBuild'])

      allow(aws_rds).to receive(:_build_template).and_return({ 'Resources' => {}, 'Outputs' => {} })
      allow(aws_rds).to receive(:_process_template_parameters)
      allow(aws_rds).to receive(:_upload_log_artefacts)

      allow(Context).to receive_message_chain('component.set_variables')
      allow(Context).to receive_message_chain('component.variable')
      allow(Context).to receive_message_chain('component.role_arn')
      allow(Context).to receive_message_chain('s3.artefact_bucket_name')

      allow(AwsHelper).to receive(:cfn_create_stack)
      allow(AwsHelper).to receive(:s3_download_objects)
      allow(Context).to receive_message_chain('component.variable')
      allow(AwsHelper).to receive(:rds_wait_for_status_available)
      allow(AwsHelper).to receive(:rds_enable_copy_tags_to_snapshot)
      allow(AwsHelper).to receive(:rds_enable_cloudwatch_logs_export)

      allow(Defaults).to receive(:log_upload_path)
      allow(Defaults).to receive(:ad_dns_zone?)

      expect { aws_rds.deploy }.not_to raise_error
    end
  end

  context '.release' do
    it 'calls release' do
      aws_rds = AwsRdsAurora.new(@test_data['ComponentName'], @test_data['ComponentDefinition']['Valid']['AuroraFullBuild'])
      expect { aws_rds.release }.not_to raise_error
    end
  end

  context '.teardown' do
    it 'calls teardown' do
      aws_rds = AwsRdsAurora.new(@test_data['ComponentName'], @test_data['ComponentDefinition']['Valid']['AuroraFullBuild'])
      allow(aws_rds).to receive(:_process_db_cluster_snapshot).and_return([])
      expect { aws_rds.teardown }.not_to raise_error
    end
  end

  context '._build_template' do
    it 'raise error on KMS' do
      aws_rds = AwsRdsAurora.new(@test_data['ComponentName'], @test_data['ComponentDefinition']['Valid']['AuroraFullBuild'])

      allow(Defaults).to receive(:component_stack_name).and_return('dummy-stack-name')

      allow(aws_rds).to receive_messages(:_process_db_subnet_group => 1,)
      allow(aws_rds).to receive_messages(:_process_db_subnet_group => 1,)

      expect { aws_rds._build_template }.to raise_error(/KMS key for application service (.*) was not found./)
    end

    it 'build successfully' do
      aws_rds = AwsRdsAurora.new(@test_data['ComponentName'], @test_data['ComponentDefinition']['Valid']['AuroraFullBuild'])

      allow(Defaults).to receive(:component_stack_name).and_return('dummy-stack-name')

      allow(aws_rds).to receive_messages(:_process_db_subnet_group => 1,)
      allow(aws_rds).to receive_messages(:_process_db_subnet_group => 1,)
      allow(Context).to receive_message_chain('kms.secrets_key_arn').and_return('kms-dummy')
      allow(AwsHelper).to receive(:rds_enable_cloudwatch_logs_export)

      expect { aws_rds._build_template }.not_to raise_error
    end
  end
end # RSpec.describe
