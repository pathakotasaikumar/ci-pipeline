$LOAD_PATH.unshift("#{BASE_DIR}/lib")
require 'consumables/aws/builders/instance_builder'
require "util/obj_to_text"
require "util/user_data"

RSpec.describe InstanceBuilder do
  before(:context) do
    @dummy_class = DummyClass.new
    @dummy_class.extend(InstanceBuilder)
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))
  end

  context '._process_instance' do
    it 'updates template when valid inputs are passed on' do
      allow(Context).to receive_message_chain('s3.artefact_bucket_name') .and_return('artefact_bucket_name')
      allow(Context).to receive_message_chain("environment.subnet_ids").and_return(["subnet-123", "subnet-456"])
      allow(Defaults).to receive_message_chain('cd_artefact_path') .and_return('cd_artefact_path')

      @test_data['UnitTest']['Input']['Configurations'].each_with_index do |configuration, index|
        template = @test_data['UnitTest']['Input']['Template']
        instance = {}
        launch_configuration = {}

        configuration.each do |name, resource|
          instance[name] = resource if resource['Type'] == 'AWS::EC2::Instance'
          launch_configuration[name] = resource if resource['Type'] == 'AWS::AutoScaling::LaunchConfiguration'
        end

        expect {
          @dummy_class._process_instance(
            template: template,
            instance_definition: instance,
            user_data: 'UserData',
            security_group_ids: ['sg-123', 'sg-456'],
            instance_profile: { "Ref" => "InstanceProfile" },
            default_instance_type: JsonTools.get(launch_configuration.values[0], "Properties.InstanceType", "m3.medium"),
            image_id: 'soe-ami-123',
            metadata: { pre_prepare: "Metadata here", auth: { "MyAuth" => "Test" } }
          )
        }.not_to raise_error
        expect(template).to eq @test_data['UnitTest']['Output']['_process_bake_instance'][index]
      end
    end
  end

  context '.add_recovery_alarm' do
    it 'adds CloudWatch recovery alarm to aws/instance component definition' do
      template = { "Resources" => {} }
      expect {
        @dummy_class._add_recovery_alarm(
          template: template,
          instance: "test-instance"
        )
      }.not_to raise_error
      expect(template).to eq @test_data['UnitTest']['Output']['_add_recovery_alarm']
    end
  end

  context '_pipeline_feature_hash_builder' do
    it 'returns pipeline_feature_hash_builder  - empty value' do
      expect(@dummy_class._pipeline_feature_hash_builder({})).to eq({})
    end

    it 'returns datadog features value' do
      output = { "features" => { "datadog" => { "status" => "enabled", "apikey" => "testkey" } } }

      mock_datadog = double(Object)
      allow(mock_datadog).to receive(:feature_properties).and_return({ "status" => "enabled", "apikey" => "testkey" })
      allow(mock_datadog).to receive(:name).and_return("datadog")
      expect(@dummy_class._pipeline_feature_hash_builder([mock_datadog])).to eq(output)
    end
  end

  context '_upload_cd_artefacts' do
    it 'returns successfully for :rhel' do
      allow(AwsHelper).to receive(:s3_upload_file)
      allow(AwsHelper).to receive(:s3_put_object)
      allow(Context).to receive_message_chain('component.dump_variables').and_return([])
      allow(Context).to receive_message_chain('s3.artefact_bucket_name').and_return('dummy-bucket-name')
      expect {
        @dummy_class._upload_cd_artefacts(
          component_name: 'dummy',
          platform: :rhel,
          soe_ami_id: 'dummy-ami-id',
          files: {},
          objects: {},
          context_skip_keys: [],
          pipeline_features: {}
        )
      }.not_to raise_exception
    end

    it 'returns successfully for :windows' do
      allow(AwsHelper).to receive(:s3_upload_file)
      allow(AwsHelper).to receive(:s3_put_object)
      allow(Context).to receive_message_chain('component.dump_variables').and_return([])
      allow(Context).to receive_message_chain('s3.artefact_bucket_name').and_return('dummy-bucket-name')
      expect {
        @dummy_class._upload_cd_artefacts(
          component_name: 'dummy',
          platform: :windows,
          soe_ami_id: 'dummy-ami-id',
          files: {},
          objects: {},
          context_skip_keys: [],
          pipeline_features: {}
        )
      }.not_to raise_exception
    end
  end

  context '._resolve_default_ou_path' do
    it 'returns non-@default value' do
      test_values = [
        {
          current_value: 'my-value1',
          env: 'prod',
          ams: 'test_ams',
          qda: 'test_qda',
          as: 'test_as',
        },
        {
          current_value: 'my-value2',
          env: 'non_prod',
          ams: 'test_ams',
          qda: 'test_qda',
          as: 'test_as',
        }
      ]

      test_values.each do |test_value|
        expect(
          @dummy_class._resolve_default_ou_path(
            current_value: test_value[:current_value],
            ams: test_value[:ams],
            qda: test_value[:qda],
            as: test_value[:as],
            env: test_value[:env]
          )
        ).to eq test_value[:current_value]
      end
    end

    it 'returns pre-calculated value' do
      test_values = [
        {
          current_value: nil,
          env: 'prod',
          ams: 'test_ams',
          qda: 'test_qda',
          as: 'test_as',
          expected_value: 'OU=test_as,OU=test_qda,OU=test_ams,OU=Prod,DC=qcpaws,DC=qantas,DC=com,DC=au'
        },
        {
          current_value: '@default',
          env: 'non_prod',
          ams: 'test_ams',
          qda: 'test_qda',
          as: 'test_as',
          expected_value: 'OU=test_as,OU=test_qda,OU=test_ams,OU=NonProd,DC=qcpaws,DC=qantas,DC=com,DC=au'
        }
      ]

      test_values.each do |test_value|
        expect(
          @dummy_class._resolve_default_ou_path(
            current_value: test_value[:current_value],
            ams: test_value[:ams],
            qda: test_value[:qda],
            as: test_value[:as],
            env: test_value[:env]
          )
        ).to eq test_value[:expected_value]
      end
    end
  end

  context '._default_ou_path' do
    it 'returns correct OU paths' do
      test_values = [
        {
          env: 'prod',
          ams: 'test_ams',
          qda: 'test_qda',
          as: 'test_as',
          expected_value: 'OU=test_as,OU=test_qda,OU=test_ams,OU=Prod,DC=qcpaws,DC=qantas,DC=com,DC=au'
        },
        {
          env: 'non_prod',
          ams: 'test_ams',
          qda: 'test_qda',
          as: 'test_as',
          expected_value: 'OU=test_as,OU=test_qda,OU=test_ams,OU=NonProd,DC=qcpaws,DC=qantas,DC=com,DC=au'
        }
      ]

      test_values.each do |test_value|
        expect(
          @dummy_class._default_ou_path(
            ams: test_value[:ams],
            qda: test_value[:qda],
            as: test_value[:as],
            env: test_value[:env]
          )
        ).to eq test_value[:expected_value]
      end
    end

    it 'raises on incorrect params' do
      test_values = [
        {
          # env: 'prod',
          ams: 'test_ams',
          qda: 'test_qda',
          as: 'test_as'
        },
        {
          env: 'prod',
          # ams: 'test_ams',
          qda: 'test_qda',
          as: 'test_as'
        },
        {
          env: 'prod',
          ams: 'test_ams',
          # qda: 'test_qda',
          as: 'test_as'
        },
        {
          env: 'prod',
          ams: 'test_ams',
          qda: 'test_qda',
          # as:  'test_as'
        }
      ]

      expect { @dummy_class._default_ou_path }.to raise_error(ArgumentError)
      expect { @dummy_class._default_ou_path(nil) }.to raise_error(ArgumentError)

      test_values.each do |test_value|
        expect {
          @dummy_class._default_ou_path(
            ams: test_value[:ams],
            qda: test_value[:qda],
            as: test_value[:as],
            env: test_value[:env]
          )
        }.to raise_error(ArgumentError)
      end
    end
  end

  context '_ssm_platform_secret_path' do
    it 'returns _ssm_platform_secret_path' do
      allow(Defaults).to receive(:sections).and_return(
        ams: "ams01", qda: "c031", as: "01", ase: "dev", branch: "master", build: 2
      )
      expected = "/platform/ams01/c031/01/dev/master/2"
      expect(@dummy_class._ssm_platform_secret_path).to eq(expected)
    end
  end

  context '_ssm_platform_secret_parameter_arn' do
    it 'returns _ssm_platform_secret_parameter_arn' do
      allow(Defaults).to receive(:sections).and_return(
        ams: "ams01", qda: "c031", as: "01", ase: "dev", branch: "master", build: 2
      )
      region = 'ap-southeast-2'
      account_id = '123456789'
      allow(Context).to receive_message_chain('environment.region').and_return(region)
      allow(Context).to receive_message_chain('environment.account_id').and_return(account_id)
      expected = "arn:aws:ssm:#{region}:#{account_id}:parameter/platform/ams01/c031/01/dev/master/2/*"
      expect(@dummy_class._ssm_platform_secret_parameter_arn).to eq(expected)
    end
  end

  context '_ssm_parameter_arn' do
    it 'returns _ssm_parameter_arn for breakglass and qualys' do
      allow(Defaults).to receive(:sections).and_return(
        ams: "ams01", qda: "c031", as: "01", ase: "dev", branch: "master", build: 2
      )

      component_name = "TestComponent"
      expected = ["arn:aws:ssm:ap-southeast-2:123456789012:parameter/ams01-c031-01-dev-master-2-TestComponent-pwd-*",
                  "arn:aws:ssm:ap-southeast-2:123456789012:parameter/ams01-c031-01-dev-master-2-TestComponent-Qualys-*"]
      expect(@dummy_class._ssm_parameter_arn(component_name)).to eq(expected)
    end
  end
  context '_instance_qualys_key_rules' do
    it 'add qualys key policy to instance role' do
      allow(Defaults).to receive(:qualys_kms_stack_name).and_return("qcp-qualys-bootstrap")
      allow(AwsHelper).to receive(:cfn_get_stack_outputs).and_return({ "QualysKeyARN" => "arn:aws:kms:ap-southeast-2:111122223333:key/1234abcd-12ab-34cd-56ef-1234567890ab" })
      component_name = "TestComponent"
      expected = [IamSecurityRule.new(
        roles: component_name + '.InstanceRole',
        actions: ["kms:Encrypt"],
        resources: ["arn:aws:kms:ap-southeast-2:111122223333:key/1234abcd-12ab-34cd-56ef-1234567890ab"],
        condition: nil
      )]

      expect(@dummy_class._instance_qualys_key_rules(component_name: component_name)).to eq(expected)
    end
  end
end # RSpec.describe
