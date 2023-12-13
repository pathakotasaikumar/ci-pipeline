$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws")
require 'aws_autoscale'
require "#{BASE_DIR}/lib/errors/autoscale_bake_error"

RSpec.describe AwsAutoscale do
  def compare_hash(path, expected, actual)
    expect("#{path} class = #{actual.class}").to eq("#{path} class = #{expected.class}")

    expected.each do |key, value|
      if value.is_a? Hash
        compare_hash("#{path}.#{key}", value, actual[key])
      else
        expect("#{path}.#{key} = #{actual[key]}").to eq("#{path}.#{key} = #{value}")
      end
    end
  end

  before(:context) do
    @test_data = YAML.load(
      File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"),
      permitted_classes: ['IamSecurityRule', 'IpSecurityRule', 'IpPort', Symbol],
      aliases: true
    )['UnitTest']
    @component_name = @test_data['Input']['ComponentName']

    Context.component.set_variables('TestComponent', {
      'BuildNumber' => '1',
      'DeployDnsName' => 'deploy-dns-name.domain.com',
      'ReleaseDnsName' => 'release-dns-name.domain.com',
    })
  end

  context '.initialize' do
    it 'initializes successfully for valid component definition' do
      expect {
        awsAutoscale = AwsAutoscale.new(@component_name, @test_data['Input']['Initialize']['Valid'])
      }.not_to raise_error
    end
    it 'initializes successfully for valid component definition' do
      expect {
        awsAutoscale = AwsAutoscale.new(@component_name, @test_data['Input']['Initialize']['ValidWithLaunchTemplate'])
      }.not_to raise_error
    end
    it 'raises error for invalid component definitions' do
      @test_data['Input']['Initialize']['Invalid'].each_with_index do |definition, index|
        expect {
          awsAutoscale = AwsAutoscale.new(@component_name, definition)
        }.to raise_error(RuntimeError, @test_data['Output']['Initialize']['Invalid'][index]['Error'])
      end
    end
  end

  context '.security_items' do
    it 'returns security items' do
      awsAutoscale = AwsAutoscale.new(@component_name, @test_data['Input']['Initialize']['Valid'])

      mocks = @test_data['Input']['Mock']
      mocks.each { |mock|
        allow(Kernel.const_get(mock['Object'])).to receive_message_chain(mock['MessageChain']) .and_return(mock['Return'])
      }
      expect(awsAutoscale.security_items).to eq @test_data['Output']['Initialize']['Valid']['SecurityItems']
    end
  end

  context '.deploy' do
    it 'deploys component successfully with empty bake_instance' do
      awsAutoscale = AwsAutoscale.new(@component_name, @test_data['Input']['Initialize']['ValidCustomAMI'])

      allow(awsAutoscale).to receive_messages(
        :_bake_instance_template => { "Resources" => {}, "Outputs" => {} },
        :_full_template => { "Resources" => {}, "Outputs" => {} },
        :_update_security_rules => 4,
        :_upload_cd_artefacts => 5,
      )

      soe_details = {
        :id => 'id',
        :name => 'name',
        :platform => 'centos'
      }

      image_output = {
        "ImageId" => 'Id',
        "ImageName" => 'Name'
      }

      allow(Defaults).to receive(:image_by_dns) .and_return('soe_id')

      allow(AwsHelper).to receive(:ec2_get_image_details) .and_return(soe_details)
      allow(TagHelper).to receive(:get_tag_values) .and_return([{ key: "SOE_ID", value: "qf-aws-win2016-x86_64-1000.1" }])
      allow(AwsHelper).to receive(:ec2_shutdown_instance_and_create_image) .and_return(image_output)
      allow(AwsHelper).to receive(:ec2_copy_image)

      allow(Context).to receive_message_chain("component.set_variables")
      allow(Context).to receive_message_chain("component.variable")
      allow(Context).to receive_message_chain("component.replace_variables")

      allow(Defaults).to receive(:image_by_dns) .and_return('soe_id')

      allow(awsAutoscale).to receive(:_upload_cd_artefacts)
      allow(awsAutoscale).to receive(:_update_security_rules)
      allow(awsAutoscale).to receive(:security_rules)
      allow(awsAutoscale).to receive(:_build_bake_stack)
      allow(awsAutoscale).to receive(:_build_full_stack)

      allow(awsAutoscale).to receive(:deploy_ad_dns_records)

      awsAutoscale.instance_variable_set(:@bake_instance, [])

      expect { awsAutoscale.deploy }.not_to raise_error
    end

    it 'deploys component successfully with empty bake_instance and false copysource image property' do
      awsAutoscale = AwsAutoscale.new(@component_name, @test_data['Input']['Initialize']['ValidCustomAMIWithoutCopyImage'])

      allow(awsAutoscale).to receive_messages(
        :_bake_instance_template => { "Resources" => {}, "Outputs" => {} },
        :_full_template => { "Resources" => {}, "Outputs" => {} },
        :_update_security_rules => 4,
        :_upload_cd_artefacts => 5,
      )

      soe_details = {
        :id => 'id',
        :name => 'name',
        :platform => 'centos'
      }

      image_output = {
        "ImageId" => 'Id',
        "ImageName" => 'Name'
      }

      allow(Defaults).to receive(:image_by_dns) .and_return('soe_id')

      allow(AwsHelper).to receive(:ec2_get_image_details) .and_return(soe_details)
      allow(TagHelper).to receive(:get_tag_values) .and_return([{ key: "SOE_ID", value: "qf-aws-win2016-x86_64-1000.1" }])
      allow(AwsHelper).to receive(:ec2_shutdown_instance_and_create_image) .and_return(image_output)

      allow(Context).to receive_message_chain("component.set_variables")
      allow(Context).to receive_message_chain("component.variable")
      allow(Context).to receive_message_chain("component.replace_variables")

      allow(Defaults).to receive(:image_by_dns) .and_return('soe_id')

      allow(awsAutoscale).to receive(:_upload_cd_artefacts)
      allow(awsAutoscale).to receive(:_update_security_rules)
      allow(awsAutoscale).to receive(:security_rules)
      allow(awsAutoscale).to receive(:_build_bake_stack)
      allow(awsAutoscale).to receive(:_build_full_stack)

      allow(awsAutoscale).to receive(:deploy_ad_dns_records)

      awsAutoscale.instance_variable_set(:@bake_instance, [])

      expect { awsAutoscale.deploy }.not_to raise_error
    end

    it 'deploys component successfully' do
      awsAutoscale = AwsAutoscale.new(@component_name, @test_data['Input']['Initialize']['Valid'])
      allow(awsAutoscale).to receive_messages(
        :_bake_instance_template => { "Resources" => {}, "Outputs" => {} },
        :_full_template => { "Resources" => {}, "Outputs" => {} },
        :_update_security_rules => 4,
        :_upload_cd_artefacts => 5,
      )

      mocks = @test_data['Input']['Mock']
      mocks.each { |mock|
        allow(Kernel.const_get(mock['Object'])).to receive_message_chain(mock['MessageChain']) .and_return(mock['Return'])
      }
      allow(Context).to receive_message_chain('s3.secret_bucket_arn')
      allow(Context).to receive_message_chain('kms.secrets_key_arn')
      allow(Context).to receive_message_chain('component.build_number')
      allow(AwsHelper).to receive(:cfn_get_stack_outputs).and_return({ "QualysKeyARN" => "arn:aws:kms:ap-southeast-2:111122223333:key/1234abcd-12ab-34cd-56ef-1234567890ab" })
      expect { awsAutoscale.deploy }.not_to raise_error
    end

    it 'raises error when mandatory steps fail' do
      awsAutoscale = AwsAutoscale.new(@component_name, @test_data['Input']['Initialize']['Valid'])
      allow(awsAutoscale).to receive_messages(
        :_bake_instance_template => 2,
        :_full_template => 3,
        :_update_security_rules => 4,
        :_upload_cd_artefacts => 5,
      )

      mocks = @test_data['Input']['Mock']
      mocks.each { |mock|
        allow(Kernel.const_get(mock['Object'])).to receive_message_chain(mock['MessageChain']) .and_return(mock['Return'])
      }
      allow(Context).to receive_message_chain('s3.secret_bucket_arn')
      allow(Context).to receive_message_chain('kms.secrets_key_arn')
      allow(Context).to receive_message_chain('component.build_number')
      allow(AwsHelper).to receive(:cfn_get_stack_outputs).and_return({ "QualysKeyARN" => "arn:aws:kms:ap-southeast-2:111122223333:key/1234abcd-12ab-34cd-56ef-1234567890ab" })
      expect {
        allow(AwsHelper).to receive(:cfn_create_stack) .and_raise(ActionError)
        awsAutoscale.deploy
      }.to raise_error(AutoScaleBakeError, /Failed to create instance bake stack/)
    end

    it 'raises error when dns creation fails' do
      awsAutoscale = AwsAutoscale.new(@component_name, @test_data['Input']['Initialize']['Valid'])
      allow(awsAutoscale).to receive_messages(
        :_bake_instance_template => { "Resources" => {}, "Outputs" => {} },
        :_full_template => { "Resources" => {}, "Outputs" => {} },
        :_update_security_rules => 4,
        :_upload_cd_artefacts => 5,
      )

      mocks = @test_data['Input']['Mock']
      mocks.each { |mock|
        allow(Kernel.const_get(mock['Object'])).to receive_message_chain(mock['MessageChain']) .and_return(mock['Return'])
      }
      allow(Defaults).to receive(:ad_dns_zone?).and_return(true)
      allow(awsAutoscale).to receive(:deploy_ad_dns_records).and_raise(RuntimeError)
      allow(Context).to receive_message_chain('s3.secret_bucket_arn')
      allow(Context).to receive_message_chain('kms.secrets_key_arn')
      allow(AwsHelper).to receive(:cfn_get_stack_outputs).and_return({ "QualysKeyARN" => "arn:aws:kms:ap-southeast-2:111122223333:key/1234abcd-12ab-34cd-56ef-1234567890ab" })
      allow(Context).to receive_message_chain('component.build_number')
      expect {
        awsAutoscale.deploy
      }.to raise_error /Failed to deploy DNS records/
    end
  end

  context '.name_records' do
    it 'successfully executes' do
      awsAutoscale = AwsAutoscale.new(@component_name, @test_data['Input']['Initialize']['Valid'])
      name_records = awsAutoscale.name_records

      expect(name_records['DeployDnsName']).not_to eq(nil)
      expect(name_records['ReleaseDnsName']).not_to eq(nil)
    end

    it 'successfully return custom dns record sets' do
      awsAutoscale = AwsAutoscale.new(@component_name, @test_data['Input']['Initialize']['ValidWithWildcard-qcpaws'])
      name_records = awsAutoscale.name_records

      expect(name_records['DeployDnsName']).not_to eq(nil)
      expect(name_records['ReleaseDnsName']).not_to eq(nil)
      expect(name_records['CustomDeployDnsName']).not_to eq(nil)
      expect(name_records['CustomReleaseDnsName']).not_to eq(nil)
    end
  end

  context '.security_rules' do
    it 'returns security rules' do
      awsAutoscale = AwsAutoscale.new(@component_name, @test_data['Input']['Initialize']['Valid'])
      allow(Defaults).to receive(:default_inbound_sources).and_return(['sg-123456', 'sg-654321'])
      allow(AwsHelper).to receive(:cfn_get_stack_outputs).and_return({ "QualysKeyARN" => "arn:aws:kms:ap-southeast-2:111122223333:key/1234abcd-12ab-34cd-56ef-1234567890ab" })
      expect(awsAutoscale.security_rules).to include IamSecurityRule.new(
        roles: @component_name + '.InstanceRole',
        actions: [
          "autoscaling:SetInstanceProtection",
          "autoscaling:SetDesiredCapacity",
          "autoscaling:SuspendProcesses",
          "autoscaling:ResumeProcesses"
        ],
        resources: "*",
        condition: {
          "StringLike" => {
            "autoscaling:ResourceTag/Name" => Defaults.build_specific_id("*").join("-")
          }
        }
      )
    end
  end

  context '.security_rules' do
    it 'returns security rules' do
      awsAutoscale = AwsAutoscale.new(@component_name, @test_data['Input']['Initialize']['Valid'])
      allow(AwsHelper).to receive(:cfn_get_stack_outputs).and_return({ "QualysKeyARN" => "arn:aws:kms:ap-southeast-2:111122223333:key/1234abcd-12ab-34cd-56ef-1234567890ab" })
      allow(Defaults).to receive(:default_inbound_sources).and_return(['sg-123456', 'sg-654321'])
      expect(awsAutoscale.security_rules).to include IamSecurityRule.new(
        roles: @component_name + '.InstanceRole',
        actions: ["autoscaling:PutScheduledUpdateGroupAction"],
        resources: "*",
        condition: {
          "StringLike" => {
            "autoscaling:ResourceTag/Name" => Defaults.branch_specific_id("*").join("-")
          }
        }
      )
    end
  end

  context '.security_rules' do
    it 'returns security rules' do
      awsAutoscale = AwsAutoscale.new(@component_name, @test_data['Input']['Initialize']['Valid'])
      allow(AwsHelper).to receive(:cfn_get_stack_outputs).and_return({ "QualysKeyARN" => "arn:aws:kms:ap-southeast-2:111122223333:key/1234abcd-12ab-34cd-56ef-1234567890ab" })
      allow(Defaults).to receive(:default_inbound_sources).and_return(['sg-123456', 'sg-654321'])
      expect(awsAutoscale.security_rules).to include IamSecurityRule.new(
        roles: @component_name + '.InstanceRole',
        actions: ["kms:Encrypt"],
        resources: ["arn:aws:kms:ap-southeast-2:111122223333:key/1234abcd-12ab-34cd-56ef-1234567890ab"],
        condition: nil
      )
    end
  end

  context '.release_component' do
    it 'updates dns record' do
      awsAutoscale = AwsAutoscale.new(@component_name, @test_data['Input']['Initialize']['Valid'])
      allow(Util::Nsupdate).to receive_messages(:create_dns_record => 3)
      componentContext = double(ComponentContext)
      allow(componentContext).to receive_messages(:variable => '', :variables => {}, :set_variables => 3, :set_details => 4)
      allow(Context).to receive(:component). and_return(componentContext)
      expect { awsAutoscale.release }.not_to raise_error
    end
  end

  context '.teardown' do
    it 'deletes stack and dns record' do
      awsAutoscale = AwsAutoscale.new(@component_name, @test_data['Input']['Initialize']['Valid'])

      allow(AwsHelper).to receive_messages(:s3_get_object => 1,
                                           :cfn_delete_stack => 2,
                                           :ec2_delete_image => 3,
                                           :autoscaling_remove_instance_protection => 4,
                                           :autoscaling_set_capacity => 5,
                                           :autoscaling_wait_for_capacity => 6)
      allow(Util::Nsupdate).to receive_messages(:delete_dns_record => 1)
      allow(AwsHelper).to receive(:clean_up_networkinterfaces)
      expect { awsAutoscale.teardown }.not_to raise_error
    end

    it 'teardown with soe_ami' do
      awsAutoscale = AwsAutoscale.new(@component_name, @test_data['Input']['Initialize']['ValidCustomAMI'])

      allow(AwsHelper).to receive_messages(:s3_get_object => 1,
                                           :cfn_delete_stack => 2,
                                           :ec2_delete_image => 3,
                                           :autoscaling_remove_instance_protection => 4,
                                           :autoscaling_set_capacity => 5,
                                           :autoscaling_wait_for_capacity => 6)
      allow(Util::Nsupdate).to receive_messages(:delete_dns_record => 1)
      allow(Context).to receive_message_chain('component.variable').and_return('customImage')
      expect(AwsHelper).to receive(:ec2_delete_image)
      allow(AwsHelper).to receive(:clean_up_networkinterfaces)
      expect { awsAutoscale.teardown }.not_to raise_error
    end

    it 'teardown component successfully with empty bake_instance and false copysource image property' do
      awsAutoscale = AwsAutoscale.new(@component_name, @test_data['Input']['Initialize']['ValidCustomAMIWithoutCopyImage'])

      allow(AwsHelper).to receive_messages(:s3_get_object => 1,
                                           :cfn_delete_stack => 2,
                                           :autoscaling_remove_instance_protection => 4,
                                           :autoscaling_set_capacity => 5,
                                           :autoscaling_wait_for_capacity => 6)
      allow(Util::Nsupdate).to receive_messages(:delete_dns_record => 1)
      allow(AwsHelper).to receive(:clean_up_networkinterfaces)
      expect(AwsHelper).not_to receive(:ec2_delete_image)

      expect { awsAutoscale.teardown }.not_to raise_error
    end

    it 'handles error and raises warnings' do
      awsAutoscale = AwsAutoscale.new(@component_name, @test_data['Input']['Initialize']['Valid'])

      allow(Context).to receive_message_chain('component.stack_id') .and_return("stack-123")
      allow(Context).to receive_message_chain('component.variable') .and_return("ami-123")
      allow(Context).to receive_message_chain('component.security_stack_id') .and_return("sec-123")
      allow(Context).to receive_message_chain('persist.released_build_number') .and_return(nil)

      allow(AwsHelper).to receive(:clean_up_networkinterfaces)
      allow(AwsHelper).to receive(:autoscaling_remove_instance_protection)
      allow(AwsHelper).to receive(:autoscaling_set_capacity)
      allow(AwsHelper).to receive(:autoscaling_wait_for_capacity)
      allow(AwsHelper).to receive(:cfn_delete_stack) .and_raise(ActionError.new, "cfn_delete_stack error")
      allow(AwsHelper).to receive(:ec2_delete_image) .and_raise(ActionError.new, "ec2_delete_image error")

      allow(Util::Nsupdate).to receive(:delete_dns_record) .and_raise(ActionError.new, "delete_dns_record error")

      # expect(Log).to receive(:warn).with /Failed to delete component ([a-zA-Z:"]*) stack([a-zA-Z:"]*)/
      # expect(Log).to receive(:warn).with /Failed to delete AMI([a-zA-Z:"]*)/
      # expect(Log).to receive(:warn).with /Failed to delete DNS record([a-zA-Z:"]*)/
      # expect(Log).to receive(:warn).with /Failed to delete DNS record([a-zA-Z:"]*)/
      expect {
        awsAutoscale.teardown
      }.to raise_error(ActionError, /cfn_delete_stack error/)
    end
  end

  context '._get_elb_ports' do
    it 'returns array of ports specified in component definition' do
      awsAutoscale = AwsAutoscale.new(@component_name, @test_data['Input']['Initialize']['Valid'])
      expect(awsAutoscale.send :_get_elb_ports).to eq ["TCP:80", "TCP:443"]
      # dont need to test SSL protocol, we only need TCP"
    end
  end

  context '._bake_instance_template' do
    it 'returns bake instance template' do
      awsAutoscale = AwsAutoscale.new(@component_name, @test_data['Input']['Initialize']['Valid'])
      allow(Context).to receive_message_chain('component.sg_id').and_return("sg-123")
      allow(Context).to receive_message_chain('component.role_name').with("TestComponent", "InstanceRole").and_return("InstanceRoleName-123")
      allow(Context).to receive_message_chain('environment.variable') .and_return("proxy.123") # aws_proxy
      allow(Context).to receive_message_chain('s3.artefact_bucket_name') .and_return("bucket-test-123")
      allow(awsAutoscale).to receive(:_process_instance)
      allow(awsAutoscale).to receive(:_metadata_pre_prepare) .and_return({})
      allow(awsAutoscale).to receive(:_metadata_bake_post_deploy) .and_return({})
      allow(awsAutoscale).to receive(:_metadata_auth) .and_return({})

      mocks = @test_data['Input']['Mock']
      mocks.each { |mock|
        allow(Kernel.const_get(mock['Object'])).to receive_message_chain(mock['MessageChain']) .and_return(mock['Return'])
      }

      allow(Context).to receive_message_chain('environment.variable'). and_return('ami-123', ['subnet-123', 'subnet-456'])

      expect(awsAutoscale.send :_bake_instance_template).to eq @test_data['Output']['BakeInstanceTemplate']
    end

    it '_bake_instance_template calls _default_ou_path' do
      had_default_ou_path_call = false
      expected_arg = {
        ams: Defaults.sections[:ams],
        qda: Defaults.sections[:qda],
        as: Defaults.sections[:as],
        env: Defaults.sections[:env]
      }

      allow(Defaults).to receive(:dns_zone).and_return(Defaults.ad_dns_zone)
      aws_component = AwsAutoscale.new(@component_name, @test_data['Input']['Initialize']['Valid'])

      allow(aws_component).to receive(:_process_instance)
      allow(aws_component).to receive(:_process_instance_profile)
      allow(aws_component).to receive(:_process_load_balancer)
      allow(aws_component).to receive(:_process_autoscaling_group)

      # _default_ou_path should be hit
      allow(aws_component).to receive(:_default_ou_path) do |arg1|
        expect(arg1).to eq expected_arg
        had_default_ou_path_call = true
      end

      aws_component.send(
        :_bake_instance_template,
        image_id: nil,
        platform: :amazon_linux
      )

      expect(had_default_ou_path_call).to eq true
    end
  end

  context '._full_template' do
    it 'returns full template - ad' do
      aws_autoscale = AwsAutoscale.new(@component_name, @test_data['Input']['Initialize']['Valid'])

      Log.debug aws_autoscale.autoscaling_group

      @test_data['Input']['Mock'].each { |mock|
        item = receive_message_chain(mock['MessageChain'])
        item = item.with(*mock['With']) unless mock['With'].nil?
        item = item.and_return(mock['Return'])
        allow(Kernel.const_get(mock['Object'])).to item
      }
      allow(aws_autoscale).to receive(:_process_platform_secret_attachments)
      allow(Defaults).to receive(:ad_dns_zone?).and_return(true)
      allow(Time).to receive_message_chain(:now, :strftime).and_return(1111111)

      allow(aws_autoscale).to receive(:_process_platform_secret_attachments)
      allow(Context).to receive_message_chain('component.role_arn')
      template = aws_autoscale.send(
        :_full_template,
        image_id: 'ami-123',
        platform: :rhel
      )
      template['Resources']['LaunchConfiguration']['Properties'].delete('UserData')
      output = (@test_data['Output']['FullTemplate']['Unstubbed'])
      expect(template).to eq(output)
    end

    it 'returns full template - route53' do
      aws_autoscale = AwsAutoscale.new(@component_name, @test_data['Input']['Initialize']['Valid'])

      Log.debug aws_autoscale.autoscaling_group

      @test_data['Input']['Mock'].each { |mock|
        item = receive_message_chain(mock['MessageChain'])
        item = item.with(*mock['With']) unless mock['With'].nil?
        item = item.and_return(mock['Return'])
        allow(Kernel.const_get(mock['Object'])).to item
      }
      allow(aws_autoscale).to receive(:_process_platform_secret_attachments)
      allow(Defaults).to receive(:dns_zone).and_return('aws.qcp')
      allow(Time).to receive_message_chain(:now, :strftime).and_return(1111111)

      allow(Context).to receive_message_chain('component.role_arn')
      template = aws_autoscale.send(
        :_full_template,
        image_id: 'ami-123',
        platform: :rhel
      )
      output = (@test_data['Output']['FullTemplate']['Unstubbed-Route53'])
      template['Resources']['LaunchConfiguration']['Properties'].delete('UserData')
      expect(template).to eq(output)
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
      aws_component = AwsAutoscale.new(@component_name, @test_data['Input']['Initialize']['Valid'])

      allow(aws_component).to receive(:_process_instance_profile)
      allow(aws_component).to receive(:_process_load_balancer)
      allow(aws_component).to receive(:_process_autoscaling_group)
      allow(aws_component).to receive(:_process_platform_secret_attachments)
      # _default_ou_path should be hit
      allow(aws_component).to receive(:_default_ou_path) do |arg1|
        expect(arg1).to eq expected_arg
        had_default_ou_path_call = true
      end

      aws_component.send(
        :_full_template,
        image_id: nil,
        platform: :amazon_linux
      )

      expect(had_default_ou_path_call).to eq true
    end
  end

  context '.default_pipeline_features_tags' do
    it 'returns values' do
      aws_component = AwsAutoscale.new(@component_name, @test_data['Input']['Initialize']['Valid'])

      allow(Defaults).to receive(:sections) .and_return({ :env => 'nonp' })
      tags = aws_component.default_pipeline_features

      expect(tags).to include({ "CodeDeploy" => "disabled" })
      expect(tags).to include({ "Datadog" => "disabled" })

      allow(Defaults).to receive(:sections) .and_return({ :env => 'prod' })
      tags = aws_component.default_pipeline_features

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

      aws_component = AwsAutoscale.new(@component_name, @test_data['Input']['Initialize']['Valid'])
      pipeline_features = aws_component.instance_variable_get(:@pipeline_features)

      feature_hash = aws_component._pipeline_feature_hash_builder(pipeline_features)
      features = feature_hash["features"]

      expect(features["datadog"]["status"]).to eq("disabled")
      expect(features["codedeploy"]["status"]).to eq("disabled")
    end
  end

  context '._get_asg_url' do
    it 'returs value' do
      aws_component = AwsAutoscale.new(@component_name, @test_data['Input']['Initialize']['Valid'])

      test_data = 'test-1'
      expected_data = autoscaling_group_url = [
        "https://ap-southeast-2.console.aws.amazon.com/ec2/autoscaling/home?region=ap-southeast-2#",
        "AutoScalingGroups:id=#{test_data};view=history"
      ].join('')

      result = aws_component.__send__(
        :_get_asg_url,
        autoscaling_group_name: test_data
      )

      expect(result).to eq(expected_data)
    end
  end

  context '._trace_asg_url' do
    it 'calls Log.info' do
      aws_component = AwsAutoscale.new(@component_name, @test_data['Input']['Initialize']['Valid'])

      test_data = 'test-1'
      test_url = aws_component.__send__(
        :_get_asg_url,
        autoscaling_group_name: test_data
      )

      result = aws_component.__send__(
        :_trace_asg_url,
        autoscaling_group_name: test_data
      )
    end
  end

  context '._format_scaling_activities' do
    it 'executes' do
      aws_component = AwsAutoscale.new(@component_name, @test_data['Input']['Initialize']['Valid'])
      test_data = _get_test_scaling_activity

      aws_component.__send__(
        :_format_scaling_activities,
        autoscaling_group_name: "my-asg",
        scaling_activities: test_data
      )
    end
  end

  context '._poll_scaling_activities_async' do
    it 'returns thread' do
      aws_component = AwsAutoscale.new(@component_name, @test_data['Input']['Initialize']['Valid'])

      test_name = 'test-1'
      test_data = _get_test_scaling_activity

      dummy_client = double(Aws::AutoScaling::Client)
      allow(dummy_client).to receive(:describe_scaling_activities).and_return(test_data)
      allow(AwsHelper).to receive(:_autoscaling_client).and_return(dummy_client)

      result = aws_component.__send__(
        :_poll_scaling_activities_async,
        autoscaling_group_name: test_name
      )

      expect(result).not_to be(nil)
      expect(result.class).to eq(Thread)

      result.kill
    end
  end

  def _get_test_scaling_activity
    require 'ostruct'

    # example of the responce
    # https://docs.aws.amazon.com/sdkforruby/api/Aws/AutoScaling/Client.html#describe_scaling_activities-instance_method
    test_data = OpenStruct.new({
      :activities => [
        OpenStruct.new({
          :activity_id => "f6258ffc-88d8-f1ca-f9b9-fa824ee5b6ed",
          :auto_scaling_group_name => "ams03-p106-01-dev-QCPFB-204-8-amazon-AutoScalingGroup-V40CFB6IGF4P",
          :description => "Launching a new EC2 instance: i-04515d6afc4b30be6",
          :cause => "At 2018-06-14T16:29:58Z a user request update of AutoScalingGroup constraints to min: 2, max: 4, desired: 2 changing the desired capacity from 0 to 2. At 2018-06-14T16:30:20Z an instance was started in response to a difference between desired and actual capacity, increasing the capacity from 0 to 2.",
          :start_time => '2018 - 06 - 14 16: 30: 22 UTC',
          :status_code => "MidLifecycleAction",
          :progress => 40,
          :details => "{\"Subnet ID\":\"subnet-7ce5bd19\",\"Availability Zone\":\"ap-southeast-2b\"}"
        }),
        OpenStruct.new({
          :activity_id => "55358ffc-88d8-e4cb-cd6f-47a68cbdcf92",
          :auto_scaling_group_name => "ams03-p106-01-dev-QCPFB-204-8-amazon-AutoScalingGroup-V40CFB6IGF4P",
          :description => "Launching a new EC2 instance: i-06e3a7f2a49671b23",
          :cause => "At 2018-06-14T16:29:58Z a user request update of AutoScalingGroup constraints to min: 2, max: 4, desired: 2 changing the desired capacity from 0 to 2. At 2018-06-14T16:30:20Z an instance was started in response to a difference between desired and actual capacity, increasing the capacity from 0 to 2.",
          :start_time => '2018 - 06 - 14 16: 30: 22 UTC',
          :status_code => "MidLifecycleAction",
          :progress => 40,
          :details => "{\"Subnet ID\":\"subnet-c16223b6\",\"Availability Zone\":\"ap-southeast-2a\"}"
        })
      ]
    })

    test_data
  end

  context '._poll_scaling_activities' do
    it 'executes' do
      aws_component = AwsAutoscale.new(@component_name, @test_data['Input']['Initialize']['Valid'])

      test_name = 'test-1'
      test_data = _get_test_scaling_activity

      dummy_client = double(Aws::AutoScaling::Client)
      allow(dummy_client).to receive(:describe_scaling_activities).and_return(test_data)
      allow(AwsHelper).to receive(:_autoscaling_client).and_return(dummy_client)

      result = aws_component.__send__(
        :_poll_scaling_activities,
        autoscaling_group_name: test_name,
        max_attempts: 1,
        poll_frequency: 0.05
      )
    end
  end

  context '._create_scaling_poll_thread' do
    it 'executes' do
      aws_component = AwsAutoscale.new(@component_name, @test_data['Input']['Initialize']['Valid'])

      test_name = 'test-1'
      test_data = _get_test_scaling_activity

      dummy_client = double(Aws::AutoScaling::Client)
      allow(dummy_client).to receive(:describe_scaling_activities).and_return(test_data)
      allow(AwsHelper).to receive(:_autoscaling_client).and_return(dummy_client)

      result = aws_component.__send__(
        :_create_scaling_poll_thread,
        autoscaling_group_name: test_name
      )

      expect(result).not_to be(nil)
      expect(result.class).to eq(Thread)
    end
  end

  context '._cleanup_scaling_poll_thread' do
    it 'executes' do
      aws_component = AwsAutoscale.new(@component_name, @test_data['Input']['Initialize']['Valid'])

      test_name = 'test-1'
      test_data = _get_test_scaling_activity

      dummy_client = double(Aws::AutoScaling::Client)
      allow(dummy_client).to receive(:describe_scaling_activities).and_return(test_data)
      allow(AwsHelper).to receive(:_autoscaling_client).and_return(dummy_client)

      # should be ok on nil
      aws_component.__send__(
        :_cleanup_scaling_poll_thread,
        asg_activities_thread: nil
      )

      # should be ok on stopping thread
      thread = Thread.new { while true do puts 'test'; sleep(30); end }

      Log.info "Thread status before cleanup: #{thread.status}"
      aws_component.__send__(
        :_cleanup_scaling_poll_thread,
        asg_activities_thread: thread
      )

      # false -> When this thread is terminated normally
      # https://ruby-doc.org/core-2.2.0/Thread.html#method-i-status

      Log.info "Thread status after cleanup: #{thread.status}"
      expect(thread.status).to eq(false)
    end
  end
end # RSpec.describe
