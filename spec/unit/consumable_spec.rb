$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib"))
require 'consumable.rb'

RSpec.describe Consumable do
  include_examples "shared context"

  before(:context) do
    test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))
    @valid_definitions = test_data["Definition"]["Valid"]
    @definition_with_autoscale_type = @valid_definitions["AutoScale"]
    @definition_with_autoscale_type_with_features = @valid_definitions["AutoScaleWithFeatures"]
    @definition_with_rdsmysql_type = @valid_definitions["RdsMysql"]
    @definition_with_rdsoracle_type = @valid_definitions["RdsOracle"]
    @definition_with_rdssqlserver_type = @valid_definitions["RdsSqlserver"]
    @definition_with_rdspostgresql_type = @valid_definitions["RdsPostgresql"]
    @definition_with_sqs_type = @valid_definitions["Sqs"]

    @results = test_data["Results"]

    invalid_definitions = test_data["Definition"]["Invalid"]
    @definition_with_invalid_type = invalid_definitions["Type"]
    @definition_with_no_stage_key = invalid_definitions["NoStage"]
    @definition_with_number_as_stage_key = invalid_definitions["Stage"]

    @valid_component_name = "some_component"
    @invalid_component_name = "#@#@#! @@#!$)(*)(*&WQE"

    @source_folder_path = "#{BASE_DIR}/platform"
    @yaml_files = Dir["#{@source_folder_path}/*.yaml"]
  end

  context '.initialize' do
    it 'accepts valid component name' do
      expect { Consumable.new(@valid_component_name, @definition_with_autoscale_type) }.not_to raise_error
    end

    it 'does not accept invalid component name' do
      expect { Consumable.new(@invalid_component_name, @definition_with_autoscale_type) }.to raise_error(ArgumentError)
    end

    it'throws exception if Stage key is not found in definition' do
      expect { Consumable.new(@valid_component_name, @definition_with_no_stage_key) }.to raise_error(ArgumentError)
    end

    it'throws exception if Stage key is not a string' do
      expect { Consumable.new(@valid_component_name, @definition_with_number_as_stage_key) }.to raise_error(ArgumentError)
    end
  end

  def _get_consumable_instance
    Consumable.new('dummy-test', {
      'Stage' => 'stage 1',
      'Type' => 'type 2'
    })
  end

  context '.security_items' do
    it 'requires override' do
      consumable = _get_consumable_instance

      expect {
        consumable.security_items
      }.to raise_error(/Must override method 'security_items' in consumable sub class/)
    end
  end

  context '.security_rules' do
    it 'requires override' do
      consumable = _get_consumable_instance

      expect {
        consumable.security_rules
      }.to raise_error(/Must override method 'security_rules' in consumable sub class/)
    end
  end

  context '.deploy' do
    it 'requires override' do
      consumable = _get_consumable_instance

      expect {
        consumable.deploy
      }.to raise_error(/Must override method 'deploy' in consumable sub class/)
    end
  end

  context '.teardown' do
    it 'requires override' do
      consumable = _get_consumable_instance

      expect {
        consumable.teardown
      }.to raise_error(/Must override method 'teardown' in consumable sub class/)
    end
  end

  context '.name_records' do
    it 'returns name_records' do
      consumable = _get_consumable_instance
      name_records = consumable.name_records

      expect(name_records.class).to eq(Hash)

      expect(name_records['DeployDnsName']).not_to eq(nil)
      expect(name_records['ReleaseDnsName']).not_to eq(nil)
    end
  end

  context '.finalise_security_rules' do
    it 'finilizes security rules' do
      consumable = _get_consumable_instance
      name_records = consumable.name_records

      allow(consumable).to receive(:_update_security_rules)
      allow(consumable).to receive(:security_rules)
      consumable.finalise_security_rules
    end
  end

  context '.default_pipeline_features_tags' do
    it 'returns default values' do
      consumable = _get_consumable_instance

      # nonp
      allow(Defaults).to receive(:sections) .and_return({ :env => 'nonp' })
      expect(consumable.default_pipeline_features)
        .to eq(
          {
            "Datadog" => "disabled"
          }
        )

      # prod
      allow(Defaults).to receive(:sections) .and_return({ :env => 'prod' })
      expect(consumable.default_pipeline_features)
        .to eq(
          {
            "Datadog" => "disabled"
          }
        )

      # exception
      allow(Defaults).to receive(:sections) .and_return({ :env => 'bla!' })
      expect { consumable.default_pipeline_features }.to raise_error(/Unknown environment/)
    end
  end

  context '.teardown_security_items' do
    it 'raises on deletion failure' do
      consumable = _get_consumable_instance

      allow(Context).to receive_message_chain('component.security_stack_id') .and_raise('Custom error!')

      expect {
        consumable.teardown_security_items
      }.to raise_error(/Custom error!/)
    end

    it 'deletes stack' do
      consumable = _get_consumable_instance

      stack_id = 'my-stack-id'

      allow(Context).to receive_message_chain('component.security_stack_id') .and_return(stack_id)
      allow(AwsHelper).to receive(:cfn_delete_stack).with(stack_id)

      consumable.teardown_security_items
    end

    it 'does nothing on empty stack' do
      consumable = _get_consumable_instance

      stack_id = 'my-stack-id'
      allow(Context).to receive_message_chain('component.security_stack_id') .and_return(nil)

      consumable.teardown_security_items
    end
  end

  context '.teardown_security_rules' do
    it 'does not raise on deletion failure' do
      consumable = _get_consumable_instance

      allow(Defaults).to receive(:security_rules_stack_name) .and_raise('Custom error!')

      expect {
        consumable.teardown_security_rules
      }.not_to raise_error
    end

    it 'deletes stack' do
      consumable = _get_consumable_instance

      stack_id = 'my-stack-id'

      allow(Defaults).to receive(:security_rules_stack_name)
      allow(AwsHelper).to receive(:cfn_stack_exists) .and_return(stack_id)
      allow(AwsHelper).to receive(:cfn_delete_stack).with(stack_id)

      consumable.teardown_security_rules
    end

    it 'does nothing on empty stack' do
      consumable = _get_consumable_instance

      allow(Defaults).to receive(:security_rules_stack_name)
      allow(AwsHelper).to receive(:cfn_stack_exists) .and_return(nil)

      consumable.teardown_security_rules
    end
  end

  context '.load_actions' do
    it 'raises error on wrong action' do
      allow(Action).to receive(:instantiate) .and_raise('Custom action load error')

      # Originally this just took the first file in the platform directory
      # But occasionally depending on folder sorting, a template would have an action
      # I believe the test case just try for one which has no action to get the custom action load error
      file_path = "#{@source_folder_path}/alb.yaml"

      hash = YAML.load(File.read(file_path))
      component_name = File.basename file_path, (File.extname file_path)
      component = Consumable.instantiate(component_name, hash)

      expect {
        actions = component.load_actions({
          "Stage1" => [
            "Action1",
            "Action2"
          ]
        })
      }.to raise_error(/Custom action load error/)
    end
  end

  context '.instantiate' do
    # temporary fix to get unit test coverage up, that should later have YAML based components
    # QCP-1393
    # QCP-1394
    it 'returns non-YAML bases components' do
      hashes = {
        'kms' => {
          'Type' => 'aws/kms',
          'Stage' => "01-sample",
          'Persist' => false,
          'IngressPoint' => true
        },

        'dummy' => {
          'Type' => 'aws/dummy',
          'Stage' => "01-sample",
          'Persist' => false,
          'IngressPoint' => true
        }
      }

      hashes.keys.each do |key|
        hash = hashes[key]
        component_name = key

        component = Consumable.instantiate(component_name, hash)
        expect(component).not_to be(nil)
      end
    end

    it 'return components' do
      allow(Context).to receive_message_chain('environment.persist_override')

      allow(Context).to receive_message_chain('environment.variable')
        .with('api_gateway_admin_url_nonp', nil)
        .and_return('http://dummy')

      allow(Context).to receive_message_chain('environment.variable')
        .with('api_gateway_username', nil)
        .and_return('dummy-user')

      allow(Context).to receive_message_chain('environment.variable')
        .with('api_gateway_password', nil)
        .and_return('dummy-pass')

      allow(Context).to receive_message_chain('environment.variable')
        .with('api_gateway_custom_key', nil)
        .and_return('dummy-pass')

      allow(Context).to receive_message_chain('environment.variable')
        .with('public_s3_content_bucket_nonp', nil)
        .and_return('dummy-bucket')

      allow(Context).to receive_message_chain('environment.variable')
        .with('puppet_qcp_lri_nonproduction', 'qcp_lri_nonproduction')
        .and_return(nil)

      allow(Context).to receive_message_chain('environment.variable')
        .with('puppet_server', 'productionpuppet1-mfz0reorujyd0tfo.ap-southeast-2.opsworks-cm.io')
        .and_return(nil)

      allow(Context).to receive_message_chain('environment.experimental?')
        .and_return(true)

      @yaml_files.each do |file_path|
        # Log.debug " loading component from #{file_path}"
        hash = YAML.load(File.read(file_path))
        component_name = File.basename file_path, (File.extname file_path)

        component = Consumable.instantiate(component_name, hash)

        expect(component).not_to be(nil)
      end
    end
  end

  context '.ingress?' do
    it 'returns true' do
      consumable = _get_consumable_instance

      consumable.instance_variable_set(:@definition, { "IngressPoint" => 'true' })
      expect(consumable.ingress?).to eq(true)
    end

    it 'returns false' do
      consumable = _get_consumable_instance

      consumable.instance_variable_set(:@definition, { "IngressPoint" => 'false' })
      expect(consumable.ingress?).to eq(false)
    end
  end

  context '._clean_ad_deployment_dns_record' do
    it 'returns on ad_dns_zone || custom_buildNumber' do
      consumable = _get_consumable_instance

      allow(Defaults).to receive(:ad_dns_zone?) .and_return(false)
      allow(Defaults).to receive_message_chain("environment.variable").with('custom_buildNumber', nil) .and_return(nil)

      consumable.send(:_clean_ad_deployment_dns_record)
    end

    it 'raises error on failed DNS deletion' do
      consumable = _get_consumable_instance

      allow(Defaults).to receive(:ad_dns_zone?) .and_return(true)
      allow(Defaults).to receive_message_chain("environment.variable").with('custom_buildNumber', nil) .and_return(nil)

      allow_any_instance_of(Util::Nsupdate).to receive(:delete_dns_record) .and_raise("Coudn't delete DNS")
      allow(Defaults).to receive(:release_dns_name) .and_return('http://localhost.local')
      allow(Defaults).to receive(:ad_dns_zone)

      expect {
        consumable.send(:_clean_ad_deployment_dns_record)
      }.to raise_error(/Failed to delete deployment DNS record/)
    end
  end

  context '._clean_ad_release_dns_record' do
    it 'returns on non-released builds' do
      consumable = _get_consumable_instance

      allow(Context).to receive_message_chain("persist.released_build?") .and_return(false)
      allow(Context).to receive_message_chain("persist.released_build_number") .and_return(1)

      # allow_any_instance_of(Util::Nsupdate).to receive(:delete_dns_record) .and_return({})

      consumable.send(:_clean_ad_release_dns_record)
    end

    it 'raises error on failed DNS deletion' do
      consumable = _get_consumable_instance

      allow(Context).to receive_message_chain("persist.released_build?") .and_return(true)
      allow(Context).to receive_message_chain("persist.released_build_number") .and_return(10)

      allow(Defaults).to receive(:release_dns_name) .and_raise("Coudn't delete DNS")
      allow(Defaults).to receive(:ad_dns_zone)

      expect {
        consumable.send(:_clean_ad_release_dns_record)
      }.to raise_error(/Failed to delete release DNS record/)
    end

    it 'calls release_dns_name on released builds' do
      consumable = _get_consumable_instance

      allow(Context).to receive_message_chain("persist.released_build?") .and_return(true)
      allow(Context).to receive_message_chain("persist.released_build_number") .and_return(10)

      allow(Defaults).to receive(:release_dns_name) .and_return('http://localhost.local')
      allow(Defaults).to receive(:ad_dns_zone)

      allow_any_instance_of(Util::Nsupdate).to receive(:delete_dns_record) .and_return({})
      consumable.send(:_clean_ad_release_dns_record)
    end
  end

  context '.instantiate' do
    it 'does not accept invalid consumable type' do
      expect { Consumable.instantiate(@valid_component_name, @definition_with_invalid_type) }.to raise_error(RuntimeError)
    end

    it 'accept valid consumable type and return an instance' do
      expect(Consumable.instantiate(@valid_component_name, @definition_with_autoscale_type)).to be_a_kind_of(AwsAutoscale)
      expect(Consumable.instantiate(@valid_component_name, @definition_with_rdsmysql_type)).to be_a_kind_of(AwsRdsMysql)
      expect(Consumable.instantiate(@valid_component_name, @definition_with_rdsoracle_type)).to be_a_kind_of(AwsRdsOracle)
      expect(Consumable.instantiate(@valid_component_name, @definition_with_rdssqlserver_type)).to be_a_kind_of(AwsRdsSqlserver)
      expect(Consumable.instantiate(@valid_component_name, @definition_with_rdspostgresql_type)).to be_a_kind_of(AwsRdsPostgresql)
      expect(Consumable.instantiate(@valid_component_name, @definition_with_sqs_type)).to be_a_kind_of(AwsSqs)
    end
  end

  context '.instantiate_all' do
    it 'accepts valid @component_definitions and returns list of consumables' do
      expect { Consumable.instantiate_all(@valid_definitions) }.not_to raise_error
    end
  end

  context 'pipeline_features' do
    consumable = Consumable.new("test", { 'Stage' => '00' })

    it 'returns nonprod default default_pipeline_features_tags ' do
      allow(Defaults).to receive(:sections).and_return(
        ams: "AMS01", qda: "C031", as: "01", env: "nonp"
      )

      expect(consumable.send(:default_pipeline_features))
        .to eq(
          {
            "Datadog" => "disabled"
          }
        )
    end

    it 'returns nonprod default default_pipeline_features_tags ' do
      allow(Defaults).to receive(:sections).and_return(
        ams: "AMS01", qda: "C031", as: "01", env: "prod"
      )

      expect(consumable.send(:default_pipeline_features))
        .to eq(
          {
            "Datadog" => "disabled"
          }
        )
    end

    it 'raise error for unknown env default_pipeline_features_tags ' do
      allow(Defaults).to receive(:sections).and_return(
        ams: "AMS01", qda: "C031", as: "01", env: "unknown"
      )

      expect { consumable.send(:default_pipeline_features) }.to raise_error /Unknown environment/
    end
  end

  context '.load_features' do
    it 'successfully load default features in nonp' do
      consumable = Consumable.new("test", { 'Stage' => '00' })
      consumable.instance_variable_set(:@definition, @definition_with_autoscale_type)

      allow(Defaults).to receive(:sections).and_return(
        ams: "AMS01", qda: "C031", as: "01", env: "nonp"
      )

      component_features = consumable.load_features

      component_features.each do |feature|
        case feature.name
        when 'datadog'
          expect(feature.enabled?).to eq(false)
        when 'ips'
          expect(feature.enabled?).to eq(true)
        else
          raise "Unexpected default feature"
        end
      end
    end

    it 'successfully load custom features in nonp' do
      consumable = Consumable.new("test", { 'Stage' => '00' })
      consumable.instance_variable_set(:@definition, @definition_with_autoscale_type_with_features)

      allow(Defaults).to receive(:sections).and_return(
        ams: "AMS01", qda: "C031", as: "01", env: "nonp"
      )

      component_features = consumable.load_features
      component_features.each do |feature|
        case feature.name
        when 'datadog'
          expect(feature.enabled?).to eq(true)
        when 'qualys'
          expect(feature.enabled?).to eq(true)
        when 'codedeploy'
          expect(feature.enabled?).to eq(true)
        when 'ips'
          expect(feature.enabled?).to eq(true)
        else
          raise "Unexpected feature"
        end
      end
    end

    it 'successfully load default features in prod' do
      consumable = Consumable.new("test", { 'Stage' => '00' })
      consumable.instance_variable_set(:@definition, @definition_with_autoscale_type)

      allow(Defaults).to receive(:sections).and_return(
        ams: "AMS01", qda: "C031", as: "01", env: "prod"
      )

      component_features = consumable.load_features

      component_features.each do |feature|
        case feature.name
        when 'datadog'
          expect(feature.enabled?).to eq(false)
        when 'ips'
          expect(feature.enabled?).to eq(true)
        else
          raise "Unexpected default feature"
        end
      end
    end

    it 'successfully load custom features in prod' do
      consumable = Consumable.new("test", { 'Stage' => '00' })
      consumable.instance_variable_set(:@definition, @definition_with_autoscale_type_with_features)

      allow(Defaults).to receive(:sections).and_return(
        ams: "AMS01", qda: "C031", as: "01", env: "prod"
      )

      component_features = consumable.load_features
      component_features.each do |feature|
        case feature.name
        when 'datadog'
          expect(feature.enabled?).to eq(true)
        when 'qualys'
          expect(feature.enabled?).to eq(true)
        when 'codedeploy'
          expect(feature.enabled?).to eq(true)
        when 'ips'
          expect(feature.enabled?).to eq(true)
        else
          raise "Unexpected feature"
        end
      end
    end
  end

  context '.deploy_security_items' do
    it 'deploys security items' do
      consumable = _get_consumable_instance

      allow(Context).to receive_message_chain('component.stack_id').and_return('1')
      allow(Context).to receive_message_chain('component.build_number').and_return('2')

      expect {
        consumable.deploy_security_items
      }.not_to raise_error
    end

    it 'deploys security items' do
      consumable = _get_consumable_instance

      allow(Defaults).to receive(:component_security_stack_name)
      allow(Defaults).to receive(:get_tags)

      allow(AwsHelper).to receive(:cfn_create_stack).and_return({})

      allow(consumable).to receive(:security_items).and_return([])
      allow(consumable).to receive(:_process_security_items).and_return([])

      expect {
        consumable.deploy_security_items
      }.not_to raise_error
    end

    it 'raise error on stack failure' do
      consumable = _get_consumable_instance

      allow(Defaults).to receive(:component_security_stack_name)
      allow(Defaults).to receive(:get_tags)

      allow(AwsHelper).to receive(:cfn_create_stack).and_raise("Can't provision stack")

      allow(consumable).to receive(:security_items).and_return([])
      allow(consumable).to receive(:_process_security_items).and_return([])

      expect {
        consumable.deploy_security_items
      }.to raise_error(/Can't provision stack/)
    end

    context '._update_security_rules' do
      it 'does not create empty stack' do
        consumable = _get_consumable_instance

        allow(Defaults).to receive(:security_rules_stack_name)
        allow(AwsHelper).to receive(:cfn_stack_exists).and_return(nil)
        allow(consumable).to receive(:_process_security_rules)

        consumable._update_security_rules(
          create_empty: false
        )
      end

      it 'force create empty stack' do
        consumable = _get_consumable_instance

        allow(Defaults).to receive(:security_rules_stack_name)
        allow(AwsHelper).to receive(:cfn_stack_exists).and_return(nil)
        allow(consumable).to receive(:_process_security_rules)

        allow(Defaults).to receive(:get_tags)
        allow(AwsHelper).to receive(:cfn_create_stack)

        consumable._update_security_rules(
          create_empty: true
        )
      end

      it 'raise on stack provision error' do
        consumable = _get_consumable_instance

        allow(Defaults).to receive(:security_rules_stack_name)
        allow(AwsHelper).to receive(:cfn_stack_exists).and_return(nil)
        allow(consumable).to receive(:_process_security_rules)

        allow(Defaults).to receive(:get_tags)
        allow(AwsHelper).to receive(:cfn_create_stack).and_raise("Can't provision stack")

        expect {
          consumable._update_security_rules(
            create_empty: true
          )
        }.to raise_error(/Can't provision stack/)
      end

      it 'updates existing stack' do
        consumable = _get_consumable_instance

        allow(Defaults).to receive(:security_rules_stack_name)
        allow(AwsHelper).to receive(:cfn_stack_exists).and_return('1')
        allow(consumable).to receive(:_process_security_rules)

        allow(Defaults).to receive(:get_tags)
        allow(AwsHelper).to receive(:cfn_update_stack)

        consumable._update_security_rules
      end

      it 'raises on updating stack provision error' do
        consumable = _get_consumable_instance

        allow(Defaults).to receive(:security_rules_stack_name)
        allow(AwsHelper).to receive(:cfn_stack_exists).and_return('1')
        allow(consumable).to receive(:_process_security_rules)

        allow(Defaults).to receive(:get_tags)
        allow(AwsHelper).to receive(:cfn_update_stack).and_raise("Can't update stack")

        expect {
          consumable._update_security_rules
        }.to raise_error(/Can't update stack/)
      end
    end

    context '._parse_security_rules' do
      it 'returns on empty rules' do
        consumable = _get_consumable_instance

        consumable._parse_security_rules(
          rules: nil
        )

        consumable._parse_security_rules(
          rules: []
        )
      end

      it 'expects array of rules' do
        consumable = _get_consumable_instance

        expect {
          consumable._parse_security_rules(
            rules: {}
          )
        }.to raise_error(/Expecting an Array for security rules/)
      end

      it 'handles :auto rules' do
        consumable = _get_consumable_instance

        security_groups = [{ 'Source' => 'MySecurityGroup' }]
        security_roles = [{ 'Source' => 'MySecurityRole' }]
        custom_roles = [{ 'Source' => 'MySecurityCustom' }]

        consumable._parse_security_rules(
          rules: security_groups,
          destination_ip: 'dest_ip'
        )

        consumable._parse_security_rules(
          rules: security_roles,
          destination_ip: 'dest_ip',
          destination_iam: 'dest_aim'
        )

        expect {
          consumable._parse_security_rules(
            rules: custom_roles,
            destination_ip: 'dest_ip',
            destination_iam: 'dest_aim'
          )
        }.to raise_error(/Could not determine security rule type from/)
      end

      it 'handles :ip rules' do
        consumable = _get_consumable_instance

        rules = [{ 'Source' => 'MySecurityGroup', 'Allow' => ['rule1', 'rule2'] }]

        allow(IpSecurityRule).to receive(:new)

        consumable._parse_security_rules(
          type: :ip,
          rules: rules,
          mappings: {
            'rule1' => '1'
          },
          destination_ip: 'sg-ip'
        )
      end

      it 'handles :iam rules' do
        consumable = _get_consumable_instance

        rules = [{ 'Source' => 'MySecurityGroup', 'Allow' => ['rule1'], 'Condition' => 'condition' }]

        allow(IamSecurityRule).to receive(:new)

        consumable._parse_security_rules(
          type: :iam,
          rules: rules,
          mappings: {
            'rule1' => '1'
          },
          destination_ip: 'sg-ip',
          destination_iam: 'sg-ip'
        )
      end

      it 'handles unknown :iam rule' do
        consumable = _get_consumable_instance

        rules = [{ 'Source' => 'MySecurityGroup', 'Allow' => ['rule1', 'rule2'], 'Condition' => 'condition' }]

        allow(IamSecurityRule).to receive(:new)

        expect {
          consumable._parse_security_rules(
            type: :iam,
            rules: rules,
            mappings: {
              'rule1' => '1'
            },
            destination_ip: 'sg-ip',
            destination_iam: 'sg-ip'
          )
        }.to raise_error(/Unknown security allow rule/)
      end
    end

    context '.get_consumables' do
      it 'returns all consumables' do
        allow(Context).to receive_message_chain('environment.persist_override')

        allow(Context).to receive_message_chain('environment.variable')
          .with('api_gateway_admin_url_nonp', nil)
          .and_return('http://dummy')

        allow(Context).to receive_message_chain('environment.variable')
          .with('api_gateway_username', nil)
          .and_return('dummy-user')

        allow(Context).to receive_message_chain('environment.variable')
          .with('api_gateway_password', nil)
          .and_return('dummy-pass')

        allow(Context).to receive_message_chain('environment.variable')
          .with('api_gateway_custom_key', nil)
          .and_return('dummy-pass')

        allow(Context).to receive_message_chain('environment.variable')
          .with('puppet_qcp_lri_nonproduction', 'qcp_lri_nonproduction')
          .and_return(nil)

        allow(Context).to receive_message_chain('environment.variable')
          .with('puppet_server', 'productionpuppet1-mfz0reorujyd0tfo.ap-southeast-2.opsworks-cm.io')
          .and_return(nil)

        allow(Context).to receive_message_chain('environment.experimental?')
          .and_return(true)

        upload_type = "public"
        if upload_type.eql? "public"
          if Defaults.sections[:env] == "prod"
            allow(Context).to receive_message_chain('environment.variable')
              .with('public_s3_content_bucket_prod', nil)
              .and_return('dummy-bucket')
          else
            allow(Context).to receive_message_chain('environment.variable')
              .with('public_s3_content_bucket_nonp', nil)
              .and_return('dummy-bucket')
          end
        else
          allow(Context).to receive_message_chain('environment.variable')
            .with('as_bucket_name', nil)
            .and_return('dummy-bucket')
        end

        @yaml_files.each do |file_path|
          # Log.debug " loading component from #{file_path}"

          hash = YAML.load(File.read(file_path))
          component_name = File.basename file_path, (File.extname file_path)

          component = Consumable.instantiate(component_name, hash)
          expect(component).not_to be(nil)
        end

        consumables = Consumable.get_consumables

        expect(consumables).not_to eq(nil)
        expect(consumables.class).to be(Hash)

        consumables.each do |key, consumable|
          expect(consumable.is_a?(Consumable)).to be(true)
        end
      end
    end

    context '.get_consumable_definitions' do
      it 'returns all consumable definitions' do
        allow(Context).to receive_message_chain('environment.persist_override')

        allow(Context).to receive_message_chain('environment.variable')
          .with('api_gateway_admin_url_nonp', nil)
          .and_return('http://dummy')

        allow(Context).to receive_message_chain('environment.variable')
          .with('api_gateway_username', nil)
          .and_return('dummy-user')

        allow(Context).to receive_message_chain('environment.variable')
          .with('api_gateway_password', nil)
          .and_return('dummy-pass')

        allow(Context).to receive_message_chain('environment.variable')
          .with('api_gateway_custom_key', nil)
          .and_return('dummy-pass')

        allow(Context).to receive_message_chain('environment.variable')
          .with('puppet_qcp_lri_nonproduction', 'qcp_lri_nonproduction')
          .and_return(nil)

        allow(Context).to receive_message_chain('environment.variable')
          .with('puppet_server', 'productionpuppet1-mfz0reorujyd0tfo.ap-southeast-2.opsworks-cm.io')
          .and_return(nil)

        allow(Context).to receive_message_chain('environment.experimental?')
          .and_return(true)

        upload_type = "public"
        if upload_type.eql? "public"
          if Defaults.sections[:env] == "prod"
            allow(Context).to receive_message_chain('environment.variable')
              .with('public_s3_content_bucket_prod', nil)
              .and_return('public_s3_content_bucket_prod')
          else
            allow(Context).to receive_message_chain('environment.variable')
              .with('public_s3_content_bucket_nonp', nil)
              .and_return('public_s3_content_bucket_nonp')
          end
        else
          allow(Context).to receive_message_chain('environment.variable')
            .with('as_bucket_name', nil)
            .and_return('dummy-bucket')
        end

        @yaml_files.each do |file_path|
          # Log.debug " loading component from #{file_path}"

          hash = YAML.load(File.read(file_path))
          component_name = File.basename file_path, (File.extname file_path)

          component = Consumable.instantiate(component_name, hash)
          expect(component).not_to be(nil)
        end

        consumable_definitions = Consumable.get_consumable_definitions

        expect(consumable_definitions).not_to eq(nil)
        expect(consumable_definitions.class).to be(Hash)

        consumable_definitions.each do |key, consumable_definition|
          expect(consumable_definition.is_a?(Hash)).to be(true)
        end
      end
    end

    context '.update_active_build?' do
      it 'returns true by default' do
        consumable = _get_consumable_instance

        expect(consumable.update_active_build?).to eq(true)
      end
    end
  end
end # RSpec.describe
