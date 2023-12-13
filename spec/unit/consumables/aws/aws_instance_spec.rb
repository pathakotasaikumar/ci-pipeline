$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws")
require 'aws_instance'
require 'builders/instance_builder'

RSpec.describe AwsInstance do
  include InstanceBuilder
  before(:context) do
    @test_data = YAML.load(
      File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"),
      permitted_classes: ['IpSecurityRule', 'IpPort', 'IamSecurityRule', Symbol]
    )['UnitTest']
    @component_name = @test_data['Input']['ComponentName']
  end

  context '.initialize' do
    it 'raises error on nil type' do
      expect {
        component = AwsInstance.new(@component_name, @test_data['Input']['Initialize']['InvalidNilType'])
      }.to raise_error(/Must specify a type for resource/)
    end

    it 'initialize with pipeline features' do
      AwsInstance.new(@component_name, @test_data['Input']['Initialize']['PipelineFeatures'])
    end

    it 'initialize with backup policy' do
      AwsInstance.new(@component_name, @test_data['Input']['Initialize']['BackupPolicy'])
    end

    it 'initialize with ScheduledAction' do
      AwsInstance.new(@component_name, @test_data['Input']['Initialize']['ScheduledAction'])
    end

    it 'initialize without error' do
      AwsInstance.new(@component_name, @test_data['Input']['Initialize']['Valid'])
    end

    it 'throws exception if multiple instances are found in definition' do
      expect {
        AwsInstance.new(@component_name, @test_data['Input']['Initialize']['Invalid']['MutlipleInstances'])
      }.to raise_error(RuntimeError, /#{@test_data['Output']['Initialize']['Invalid']['MutlipleInstances']}/)
    end

    it 'throws exception if multiple roles are found in definition' do
      expect {
        AwsInstance.new(@component_name, @test_data['Input']['Initialize']['Invalid']['IamRole'])
      }.to raise_error(RuntimeError, /#{@test_data['Output']['Initialize']['Invalid']['IamRole']}/)
    end
  end

  context '.security_items' do
    it 'returns security items' do
      awsInstance = AwsInstance.new(@component_name, @test_data['Input']['Initialize']['Valid'])
      expect(awsInstance.security_items).to eq @test_data['Output']['SecurityItems']
    end
  end

  context '.security_rules' do
    it 'returns security rules' do
      awsInstance = AwsInstance.new(@component_name, @test_data['Input']['Initialize']['Valid'])
      load_mocks @test_data['Input']['SecurityRules']['Mock']
      allow(Context).to receive_message_chain('component.build_number')
      allow(Defaults).to receive(:default_inbound_sources).and_return(['sg-123456', 'sg-654321'])
      allow(Defaults).to receive(:default_qualys_sources).and_return(['sg-2468'])
      allow(AwsHelper).to receive(:cfn_get_stack_outputs).and_return({ "QualysKeyARN" => "arn:aws:kms:ap-southeast-2:111122223333:key/1234abcd-12ab-34cd-56ef-1234567890ab" })
      expect(awsInstance.security_rules).to eq @test_data['Output']['SecurityRules']
    end
  end

  context 'post_deploy' do
    it 'checks for Qaulys features = enabled ' do
      awsInstance = AwsInstance.new(@component_name, @test_data['Input']['Initialize']['PipelineFeatures'])
      expect { awsInstance.post_deploy }.not_to raise_error
    end

    it 'checks for Qaulys features = disabled' do
      awsInstance = AwsInstance.new(@component_name, @test_data['Input']['Initialize']['PipelineFeatures1'])
      expect { awsInstance.post_deploy }.not_to raise_error
    end
  end

  context '.deploy' do
    it 'deploys component successfully' do
      load_mocks @test_data['Input']['Deploy']['Mock']
      awsInstance = AwsInstance.new(@component_name, @test_data['Input']['Initialize']['Valid'])
      allow(TagHelper).to receive(:get_tag_values) .and_return([{ key: "SOE_ID", value: "qf-aws-win2016-x86_64-1000.1" }])
      expect(awsInstance).to receive(:_update_security_rules).twice
      expect { awsInstance.deploy }.not_to raise_error
    end

    it 'deploys fails with dns creation' do
      load_mocks @test_data['Input']['Deploy']['Mock']
      allow(Context).to receive_message_chain('component.variable')
      allow(Defaults).to receive(:ad_dns_zone?).and_return(true)
      awsInstance = AwsInstance.new(@component_name, @test_data['Input']['Initialize']['Valid'])
      expect(awsInstance).to receive(:_update_security_rules).twice
      allow(awsInstance).to receive(:deploy_ad_dns_records).and_raise(RuntimeError)
      expect { awsInstance.deploy }.to raise_exception /Failed to deploy DNS records/
    end
  end

  context '.release' do
    it 'updates dns record' do
      load_mocks @test_data['Input']['Release']['Mock']
      awsInstance = AwsInstance.new(@component_name, @test_data['Input']['Initialize']['Valid'])
      expect { awsInstance.release }.not_to raise_error
    end
  end

  context '.teardown' do
    it 'deletes dns record' do
      load_mocks @test_data['Input']['Teardown']['Mock']
      awsInstance = AwsInstance.new(@component_name, @test_data['Input']['Initialize']['Valid'])
      allow(Defaults).to receive(:component_stack_name).and_return(nil)
      expect { awsInstance.teardown }.not_to raise_error
    end

    it 'delete the eni before teardown' do
      load_mocks @test_data['Input']['Teardown']['Mock']
      awsInstance = AwsInstance.new(@component_name, @test_data['Input']['Initialize']['Valid'])
      allow(Defaults).to receive(:component_stack_name).and_return("secretsmanagement_lambda")
      allow(AwsHelper).to receive(:ec2_lambda_network_interfaces).and_return('eni-12345678')
      allow(AwsHelper).to receive(:ec2_delete_network_interfaces)

      expect { awsInstance.teardown }.not_to raise_error
    end

    it 'skip eni deletion teardown' do
      load_mocks @test_data['Input']['Teardown']['Mock']
      awsInstance = AwsInstance.new(@component_name, @test_data['Input']['Initialize']['Valid'])
      allow(Defaults).to receive(:component_stack_name).and_return("secretsmanagement_lambda")
      allow(AwsHelper).to receive(:ec2_lambda_network_interfaces).and_return(nil)

      expect { awsInstance.teardown }.not_to raise_error
    end

    it 'fail to delete eni before teardown stack' do
      load_mocks @test_data['Input']['Teardown']['Mock']
      awsInstance = AwsInstance.new(@component_name, @test_data['Input']['Initialize']['Valid'])
      allow(Defaults).to receive(:component_stack_name).and_return("secretsmanagement_lambda")
      allow(AwsHelper).to receive(:ec2_lambda_network_interfaces).and_return('eni-12345678')
      allow(AwsHelper).to receive(:ec2_delete_network_interfaces).and_raise(RuntimeError)

      expect { awsInstance.teardown }.not_to raise_error
    end
  end

  context '._full_template' do
    it 'returns template' do
      allow(Defaults).to receive(:dns_zone).and_return(Defaults.ad_dns_zone)
      load_mocks @test_data['Input']['_full_template']['Mock']

      awsInstance = AwsInstance.new(@component_name, @test_data['Input']['Initialize']['Valid'])

      allow(awsInstance).to receive(:_metadata_pre_prepare) .and_return({})
      allow(awsInstance).to receive(:_metadata_pre_deploy)  .and_return({})
      allow(awsInstance).to receive(:_metadata_post_deploy) .and_return({})

      expect(awsInstance.send :_full_template).to eq @test_data['Output']['_full_template']['ad_dns_zone']
    end

    it 'returns template with route53' do
      allow(Defaults).to receive(:dns_zone).and_return(Defaults.r53_dns_zone)
      load_mocks @test_data['Input']['_full_template']['Mock']

      awsInstance = AwsInstance.new(@component_name, @test_data['Input']['Initialize']['Valid'])

      allow(awsInstance).to receive(:_metadata_pre_prepare) .and_return({})
      allow(awsInstance).to receive(:_metadata_pre_deploy)  .and_return({})
      allow(awsInstance).to receive(:_metadata_post_deploy) .and_return({})
      allow(Context.component).to receive(:replace_variables)

      expect(awsInstance.send :_full_template).to eq @test_data['Output']['_full_template']['r53_dns_zone']
    end

    it '_full_template calls _default_ou_path' do
      had_default_ou_path_call = false
      expected_arg = {
        ams: Defaults.sections[:ams],
        qda: Defaults.sections[:qda],
        as: Defaults.sections[:as],
        env: Defaults.sections[:env]
      }

      allow(Defaults).to receive(:dns_zone).and_return(Defaults.ad_dns_zone)
      awsInstance = AwsInstance.new(@component_name, @test_data['Input']['Initialize']['Valid'])

      allow(awsInstance).to receive(:_process_instance_profile) .and_return({})
      allow(awsInstance).to receive(:_metadata_pre_prepare) .and_return({})
      allow(awsInstance).to receive(:_metadata_pre_deploy) .and_return({})
      allow(awsInstance).to receive(:_metadata_post_deploy) .and_return({})
      allow(awsInstance).to receive(:_metadata_auth) .and_return({})
      allow(awsInstance).to receive(:_process_instance) .and_return({})
      allow(awsInstance).to receive(:_add_recovery_alarm) .and_return({})

      # _default_ou_path should be hit
      allow(awsInstance).to receive(:_default_ou_path) do |arg1|
        expect(arg1).to eq expected_arg
        had_default_ou_path_call = true
      end

      awsInstance.send :_full_template
      expect(had_default_ou_path_call).to eq true
    end
  end

  context '.default_pipeline_features_tags' do
    it 'returns values' do
      awsInstance = AwsInstance.new(@component_name, @test_data['Input']['Initialize']['Valid'])

      allow(Defaults).to receive(:sections) .and_return({ :env => 'nonp' })
      tags = awsInstance.default_pipeline_features

      expect(tags).to include({ "CodeDeploy" => "disabled" })
      expect(tags).to include({ "Datadog" => "disabled" })

      allow(Defaults).to receive(:sections) .and_return({ :env => 'prod' })
      tags = awsInstance.default_pipeline_features

      expect(tags).to include({ "CodeDeploy" => "disabled" })
      expect(tags).to include({ "Datadog" => "disabled" })
    end
  end

  context '._pipeline_feature_hash_builder' do
    it 'returns features hash' do
      allow(Defaults).to receive(:sections).and_return(
        ams: "AMS01", qda: "C031", as: "01", env: "nonp"
      )

      allow(Defaults).to receive(:datadog_api_keys).and_return({ "ams01-nonp" => "testkey" }.to_json)

      awsInstance = AwsInstance.new(@component_name, @test_data['Input']['Initialize']['Valid'])
      pipeline_features = awsInstance.instance_variable_get(:@pipeline_features)

      feature_hash = awsInstance._pipeline_feature_hash_builder(pipeline_features)
      features = feature_hash["features"]

      expect(features["datadog"]["status"]).to eq("disabled")
      expect(features["codedeploy"]["status"]).to eq("disabled")
    end
  end

  context '._prepare_secret_lambda_template' do
    it 'returns _prepare_secret_lambda_template template' do
      awsInstance = AwsInstance.new(@component_name, @test_data['Input']['Initialize']['Valid'])

      allow(Defaults).to receive(:secrets_bucket_name).and_return('qcp-secret-management-bucket')
      allow(Defaults).to receive(:secrets_file_location_path).and_return('platform-secrets-storage/secrets.json')
      allow(Context).to receive_message_chain('component.sg_id').and_return('group-1')
      allow(Context).to receive_message_chain('component.role_arn').and_return('secretmanagement-role-arn')
      allow(Context).to receive_message_chain('kms.secrets_key_arn')
        .and_return 'arn:aws:kms:ap-southeast-2:123456789012:key/12345678-1234-1234-1234-123456789012'
      allow(Context).to receive_message_chain('component.variable').with("pipeline", "LambdaArtefactBucketName", nil).and_return('qcp-pipeline-lambda-artefacts')
      allow(Context).to receive_message_chain('component.replace_variables')
      allow(awsInstance). to receive(:_prepare_and_upload_package_to_s3)
      expect(awsInstance.send(:_prepare_secret_lambda_template, resource_name: "SecretManagementLambda")).to eq @test_data['Output']['SecretManagementOutput']
    end
  end
end # RSpec.describe
