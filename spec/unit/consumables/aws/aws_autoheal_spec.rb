$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws")
require 'aws_autoheal'
require 'yaml'

RSpec.describe AwsAutoheal do
  @autoscaling_group_name = "AutoscalingGroup"

  before(:context) do
    @test_data = YAML.load(
      File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"),
      permitted_classes: ['IamSecurityRule', 'IpSecurityRule', 'IpPort']
    )['IntegrationTest']
    @test_output = JSON.parse(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.json"))['IntegrationTest']
    @component_name = @test_data['Input']['ComponentName']
    @AwsAutoheal = AwsAutoheal.new(@component_name, @test_data['Input']['Valid'])

    Context.environment.set_variables({ "aws_account_id" => "111111111111" })
    Context.component.set_variables(@component_name, { "VolumeAttachmentExecutionRole" => "arn:aws:iam:ap-southeast-2:111111111111:role/ExecutionRole" })
    Context.component.set_variables(@component_name, { "VolumeAttachmentNotificationRole" => "arn:aws:iam:ap-southeast-2:111111111111:role/NotificationRole" })
    Context.component.set_variables("volume1", { "MyVolumeId" => "vol-123456780" })
    Context.component.set_variables("volume2", { "MyVolumeId" => "vol-123456780" })
    Context.component.set_variables("volume", { "MyVolumeId" => "vol-123456780" })
    Context.component.set_variables("eni1", { "MyEniId" => "eni-123456780" })
    Context.component.set_variables("eni2", { "MyEniId" => "eni-123456780" })

    @volume_attachments = {}
    @network_attachments = {}

    (@test_data['Input']['Valid']['Configuration'] || {}).each do |name, resource|
      type = resource["Type"]
      case type
      when "Pipeline::Autoheal::VolumeAttachment"
        @volume_attachments[name] = resource
      when "Pipeline::Autoheal::NetworkInterfaceAttachment"
        @network_attachments[name] = resource
      end
    end
  end

  context '._process_volume_attachments' do
    it 'generates template for volume attachments' do
      template = { "Resources" => {}, "Outputs" => {} }
      allow(@AwsAutoheal).to receive(:_process_pipeline_autoscaling_action)
      expect {
        @AwsAutoheal._process_volume_attachments(
          template: template,
          autoscaling_group_name: "dummy-asg",
          volume_attachments: {},
          execution_role_arn: "dummy-execution-role-arn",
          notification_role_arn: "dummy-notification-role-arn"
        )
      }.not_to raise_error
    end
  end

  context '._process_network_attachments' do
    it 'generates template for network attachments' do
      template = { "Resources" => {}, "Outputs" => {} }
      allow(@AwsAutoheal).to receive(:_process_pipeline_autoscaling_action)
      expect {
        @AwsAutoheal._process_network_attachments(
          template: template,
          autoscaling_group_name: "dummy-asg",
          network_attachments: {},
          execution_role_arn: "dummy-role-arn",
          notification_role_arn: "dummy-role-arn"
        )
      }.not_to raise_exception
    end
  end

  context '._full_template' do
    it '_full_template calls _default_ou_path' do
      had_default_ou_path_call = false
      expected_arg = {
        ams: Defaults.sections[:ams],
        qda: Defaults.sections[:qda],
        as: Defaults.sections[:as],
        env: Defaults.sections[:env]
      }

      allow(Defaults).to receive(:dns_zone).and_return(Defaults.ad_dns_zone)
      aws_component = AwsAutoheal.new(@component_name, @test_data['Input']['Valid'])

      allow(aws_component).to receive(:_process_instance_profile)
      allow(aws_component).to receive(:_process_load_balancer)
      allow(aws_component).to receive(:_process_launch_configuration)
      allow(aws_component).to receive(:_process_autoscaling_group)
      allow(aws_component).to receive(:_process_alarms)
      allow(aws_component).to receive(:_process_volume_tagger)
      allow(aws_component).to receive(:_process_volume_attachments)
      allow(aws_component).to receive(:_process_platform_secret_attachments)
      allow(aws_component).to receive(:_process_network_attachments)
      allow(aws_component).to receive(:_process_lifecycle_hooks)
      allow(aws_component).to receive(:_process_lifecycle_hooks)
      allow(aws_component).to receive(:_parse_instance_backup_policy).and_return([])

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

  context '.security_items' do
    it 'returns security items' do
      component = AwsAutoheal.new(@component_name, @test_data['Input']['Valid'])
      expect(component.security_items).to eq @test_data['Output']['SecurityItems']
    end
  end

  context '.security_rules' do
    it 'returns security items' do
      component = AwsAutoheal.new(@component_name, @test_data['Input']['Valid'])
      allow(Defaults).to receive(:default_inbound_sources).and_return(['sg-123456', 'sg-654321'])
      allow(Defaults).to receive(:default_qualys_sources).and_return(['sg-2468'])
      allow(AwsHelper).to receive(:cfn_get_stack_outputs).and_return({ "QualysKeyARN" => "arn:aws:kms:ap-southeast-2:111122223333:key/1234abcd-12ab-34cd-56ef-1234567890ab" })
      allow(Context).to receive_message_chain('kms.secrets_key_arn').and_return('arn:aws:kms:ap-southeast-2:111122223333:key/1234abcd-12ab-34cd-56ef-1234567890ab')
      expect(component.security_rules).to eq @test_data['Output']['SecurityRules']
    end
  end

  context '._bake_instance_template' do
    it '_bake_instance_template calls _default_ou_path' do
      had_default_ou_path_call = false
      expected_arg = {
        ams: Defaults.sections[:ams],
        qda: Defaults.sections[:qda],
        as: Defaults.sections[:as],
        env: Defaults.sections[:env]
      }

      allow(Defaults).to receive(:dns_zone).and_return(Defaults.ad_dns_zone)
      aws_component = AwsAutoheal.new(@component_name, @test_data['Input']['Valid'])

      allow(aws_component).to receive(:_process_instance_profile)
      allow(aws_component).to receive(:_process_load_balancer)
      allow(aws_component).to receive(:_process_launch_configuration)
      allow(aws_component).to receive(:_process_autoscaling_group)
      allow(aws_component).to receive(:_process_alarms)
      allow(aws_component).to receive(:_process_volume_tagger)
      allow(aws_component).to receive(:_process_volume_attachments)
      allow(aws_component).to receive(:_process_network_attachments)
      allow(aws_component).to receive(:_process_lifecycle_hooks)
      allow(aws_component).to receive(:_process_instance)

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

  context '.release' do
    it 'calls release' do
      component = AwsAutoheal.new(@component_name, @test_data['Input']['Valid'])
      component.release
    end
  end

  context '.name_records' do
    it 'successfully executes' do
      aws_component = AwsAutoheal.new(@component_name, @test_data['Input']['Valid'])
      name_records = aws_component.name_records

      expect(name_records['DeployDnsName']).not_to eq(nil)
      expect(name_records['ReleaseDnsName']).not_to eq(nil)
    end

    it 'successfully return custom dns record sets' do
      aws_component = AwsAutoheal.new(@component_name, @test_data['Input']['ValidWithWildcard-qcpaws'])
      name_records = aws_component.name_records

      expect(name_records['DeployDnsName']).not_to eq(nil)
      expect(name_records['ReleaseDnsName']).not_to eq(nil)
      expect(name_records['CustomDeployDnsName']).not_to eq(nil)
      expect(name_records['CustomReleaseDnsName']).not_to eq(nil)
    end
  end

  context '.initialize' do
    it 'raises error on nil type' do
      expect {
        component = AwsAutoheal.new(@component_name, @test_data['Input']['InvalidNilType'])
      }.to raise_error(/Must specify a type for resource/)
    end

    it 'raises error on custom type' do
      expect {
        component = AwsAutoheal.new(@component_name, @test_data['Input']['InvalidCustomType'])
      }.to raise_error(/is not supported by this component/)
    end

    it 'raises error on mixinstance type' do
      expect {
        component = AwsAutoheal.new(@component_name, @test_data['Input']['MixedInstanceTypeNotSupported'])
      }.to raise_error(/MixedInstancesPolicy is not supported for aws\/autoheal component/)
    end

    # can't pass this test due to unreachable code
    # tracked in JIRA: https://jira.qantas.com.au/browse/QCP-1400
    # needs to be revisit and made green

    #  it 'raises error on invalid pipelijne features' do

    #    expect {
    #      component = AwsAutoheal.new(@component_name, @test_data['Input']['InvalidPipeineFeature'])
    #    }.to raise_error(/Pipeline::Features Properties.Features must be an a Hash/)

    #  end
  end

  context '._bake_instance_template' do
    it 'returns template' do
      component = AwsAutoheal.new(@component_name, @test_data['Input']['Valid'])

      allow(component).to receive(:_process_instance_profile)
      allow(component).to receive(:_process_instance)

      allow(component).to receive(:_metadata_pre_prepare) .and_return({})
      allow(component).to receive(:_metadata_pre_deploy) .and_return({})

      allow(Context).to receive_message_chain("s3.artefact_bucket_name")
      allow(Defaults).to receive_message_chain("cd_artefact_path")

      # normal
      result = component.send(:_bake_instance_template, image_id: '', platform: :centos)
      expect(result).to_not be(nil)

      # windows
      result = component.send(:_bake_instance_template, image_id: '', platform: :windows)
      expect(result).to_not be(nil)
    end
  end

  context '._build_bake_stack' do
    it 'returns template' do
      allow(AwsHelper).to receive(:_provisioning_credentials)
      allow(AwsHelper).to receive(:_control_credentials)

      component = AwsAutoheal.new(@component_name, @test_data['Input']['Valid'])

      allow(Context).to receive_message_chain("component.variable")
      allow(Context).to receive_message_chain("component.role_name")
      allow(Context).to receive_message_chain("component.set_variables")
      allow(Context).to receive_message_chain("component.sg_id")
      allow(Context).to receive_message_chain("component.stack_id")

      allow(AwsHelper).to receive(:cfn_update_stack)
      allow(AwsHelper).to receive(:cfn_create_stack)
      allow(AwsHelper).to receive(:s3_download_objects)

      allow(component).to receive(:_bake_instance_template)

      # normal
      component.send(
        :_build_bake_stack,
        soe_ami_id: '',
        soe_ami_name: '',
        platform: :centos
      )
    end

    it 'raises error on failed stack' do
      allow(AwsHelper).to receive(:_provisioning_credentials)
      allow(AwsHelper).to receive(:_control_credentials)

      component = AwsAutoheal.new(@component_name, @test_data['Input']['Valid'])

      allow(component).to receive(:_bake_instance_template)

      allow(Context).to receive_message_chain("component.variable")
      allow(Context).to receive_message_chain("component.role_name")
      allow(Context).to receive_message_chain("component.set_variables")
      allow(Context).to receive_message_chain("component.sg_id")
      allow(Context).to receive_message_chain("component.stack_id")

      allow(AwsHelper).to receive(:cfn_create_stack) .and_raise('cannot create stack')
      allow(AwsHelper).to receive(:s3_download_objects)

      expect {
        component.send(
          :_build_bake_stack,
          soe_ami_id: '',
          soe_ami_name: '',
          platform: :centos
        )
      }.to raise_error(RuntimeError, /cannot create stack/)
    end
  end

  context '._build_full_stack' do
    def _configure_build_full_stack_mock(component)
      allow(Context).to receive_message_chain("component.variable")
      allow(Context).to receive_message_chain("component.role_name")
      allow(Context).to receive_message_chain("component.set_variables")
      allow(Context).to receive_message_chain("component.sg_id")
      allow(Context).to receive_message_chain("component.stack_id")

      allow(AwsHelper).to receive(:cfn_update_stack)
      allow(AwsHelper).to receive(:cfn_create_stack)
      allow(AwsHelper).to receive(:s3_download_objects)

      allow(component).to receive(:_full_template) .and_return({ "Resources" => {}, "Outputs" => {} })
      allow(component).to receive(:_process_autoscaling_group)
      allow(component).to receive(:_process_load_balancer)
    end

    it 'returns template' do
      component = AwsAutoheal.new(@component_name, @test_data['Input']['Valid'])

      _configure_build_full_stack_mock component

      # normal
      component.send(:_build_full_stack, platform: :centos)
    end

    it 'returns template for empty bake_instance' do
      component = AwsAutoheal.new(@component_name, @test_data['Input']['Valid'])

      _configure_build_full_stack_mock component

      component.instance_variable_set(:@bake_instance, [])
      component.send(:_build_full_stack, platform: :centos)
    end
  end

  context '._full_template' do
    it '_full_template calls _default_ou_path' do
      had_default_ou_path_call = false
      expected_arg = {
        ams: Defaults.sections[:ams],
        qda: Defaults.sections[:qda],
        as: Defaults.sections[:as],
        env: Defaults.sections[:env]
      }

      allow(Defaults).to receive(:dns_zone).and_return(Defaults.ad_dns_zone)
      aws_component = AwsAutoheal.new(@component_name, @test_data['Input']['Valid'])

      allow(aws_component).to receive(:_process_instance_profile)
      allow(aws_component).to receive(:_process_load_balancer)
      allow(aws_component).to receive(:_process_launch_configuration)
      allow(aws_component).to receive(:_process_autoscaling_group)
      allow(aws_component).to receive(:_process_alarms)
      allow(aws_component).to receive(:_process_volume_tagger)
      allow(aws_component).to receive(:_process_volume_attachments)
      allow(aws_component).to receive(:_process_platform_secret_attachments)
      allow(aws_component).to receive(:_process_network_attachments)
      allow(aws_component).to receive(:_process_lifecycle_hooks)

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

    it 'returns template' do
      component = AwsAutoheal.new(@component_name, @test_data['Input']['Valid'])

      allow(component).to receive(:_process_load_balancer)

      allow(component).to receive(:_metadata_pre_prepare) .and_return({})
      allow(component).to receive(:_metadata_pre_deploy) .and_return({})
      allow(component).to receive(:_metadata_post_deploy) .and_return({})
      allow(component).to receive(:_metadata_auth) .and_return({})

      allow(component).to receive(:_process_launch_configuration)
      allow(component).to receive(:_process_autoscaling_group)
      allow(component).to receive(:_process_scheduled_actions)
      allow(component).to receive(:_process_alarms)
      allow(component).to receive(:_process_volume_attachments)
      allow(component).to receive(:_process_network_attachments)
      allow(component).to receive(:_process_platform_secret_attachments)
      allow(component).to receive(:_process_lifecycle_hooks)
      allow(component).to receive(:_parse_instance_backup_policy)
      allow(component).to receive(:_process_backup_policy)
      allow(component).to receive(:_process_deploy_r53_dns_records)

      allow(UserData).to receive(:load_aws_userdata)

      # normal
      result = component.send(:_full_template, image_id: '', platform: :centos)
      expect(result).to_not be(nil)

      # windows
      result = component.send(:_full_template, image_id: '', platform: :windows)
      expect(result).to_not be(nil)

      # empty bake instance
      component.instance_variable_set(:@bake_instance, [])
      result = component.send(:_full_template, image_id: '', platform: :windows)
      expect(result).to_not be(nil)

      # r53_dns_records
      allow(Defaults).to receive(:ad_dns_zone?) .and_return (false)
      component.instance_variable_set(:@load_balancer, [1, 2, 3])

      result = component.send(:_full_template, image_id: '', platform: :windows)
      expect(result).to_not be(nil)
    end
  end

  context '.teardown' do
    it 'teardown' do
      component = AwsAutoheal.new(@component_name, @test_data['Input']['Valid'])
      _configure_teardown_mock component

      component.teardown
    end

    it 'teardown by autoscaling group name' do
      component = AwsAutoheal.new(@component_name, @test_data['Input']['Valid'])
      _configure_teardown_mock component

      allow(Context).to receive_message_chain("component.variable") .and_return('group')

      component.teardown
    end

    it 'teardown with soe_ami' do
      component = AwsAutoheal.new(@component_name, @test_data['Input']['ValidWithSOE'])
      _configure_teardown_mock component

      allow(Context).to receive_message_chain("component.variable") .and_return('group')
      expect(AwsHelper).to receive(:ec2_delete_image)
      component.teardown
    end

    it 'teardown component successfully with empty bake_instance and false copysource image property' do
      component = AwsAutoheal.new(@component_name, @test_data['Input']['ValidWithSOEWithoutCopy'])
      _configure_teardown_mock component

      allow(Context).to receive_message_chain("component.variable") .and_return('group')

      expect(AwsHelper).not_to receive(:ec2_delete_image)

      component.teardown
    end
  end

  def _configure_teardown_mock(component)
    _configure_deploy_mock component

    allow(AwsHelper).to receive(:autoscaling_set_capacity)
    allow(AwsHelper).to receive(:autoscaling_wait_for_capacity)

    allow(AwsHelper).to receive(:cfn_delete_stack)
    allow(AwsHelper).to receive(:ec2_delete_image)

    allow(AwsHelper).to receive(:clean_up_networkinterfaces)

    allow(component).to receive(:_clean_ad_deployment_dns_record)
    allow(component).to receive(:_clean_ad_release_dns_record)
  end

  def _configure_deploy_mock(component)
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
    allow(AwsHelper).to receive(:ec2_shutdown_instance_and_create_image) .and_return(image_output)
    allow(AwsHelper).to receive(:ec2_copy_image)

    allow(Context).to receive_message_chain("component.set_variables")
    allow(Context).to receive_message_chain("component.variable")
    allow(Context).to receive_message_chain("component.replace_variables")

    allow(component).to receive(:_upload_cd_artefacts)
    allow(component).to receive(:_update_security_rules)
    allow(component).to receive(:security_rules)
    allow(component).to receive(:_build_bake_stack)
    allow(component).to receive(:_build_full_stack)
  end

  context '.deploy' do
    it 'raises error on :unknown image' do
      component = AwsAutoheal.new(@component_name, @test_data['Input']['Valid'])

      soe_details = {
        :id => 'id',
        :name => 'name',
        :platform => :unknown
      }

      allow(Defaults).to receive(:image_by_dns) .and_return('soe_id')
      allow(AwsHelper).to receive(:ec2_get_image_details) .and_return(soe_details)

      expect {
        component.deploy
      }.to raise_error(/Cannot determine operating system type of image/)
    end

    it 'deploys with bake instance' do
      component = AwsAutoheal.new(@component_name, @test_data['Input']['Valid'])
      _configure_deploy_mock component

      allow(component).to receive(:deploy_ad_dns_records)
      allow(TagHelper).to receive(:get_tag_values) .and_return([{ key: "SOE_ID", value: "qf-aws-win2016-x86_64-1000.1" }])

      component.deploy
    end

    it 'deploy fails on empty soe_ami' do
      component = AwsAutoheal.new(@component_name, @test_data['Input']['Valid'])
      _configure_deploy_mock component

      component.instance_variable_set(:@bake_instance, [])

      allow(component).to receive(:deploy_ad_dns_records)

      expect {
        component.deploy
      }.to raise_error(/No BakeInstance resource or ImageId specified in LaunchConfiguration resource/)
    end

    it 'deploys with soe_ami' do
      component = AwsAutoheal.new(@component_name, @test_data['Input']['ValidWithSOE'])
      _configure_deploy_mock component

      component.instance_variable_set(:@bake_instance, [])

      allow(component).to receive(:deploy_ad_dns_records)
      allow(TagHelper).to receive(:get_tag_values) .and_return([{ key: "SOE_ID", value: "qf-aws-win2016-x86_64-1000.1" }])

      component.deploy
    end

    it 'deploys component successfully with empty bake_instance and false copysource image property' do
      component = AwsAutoheal.new(@component_name, @test_data['Input']['ValidWithSOEWithoutCopy'])
      _configure_deploy_mock component

      component.instance_variable_set(:@bake_instance, [])

      allow(component).to receive(:deploy_ad_dns_records)
      allow(TagHelper).to receive(:get_tag_values) .and_return([{ key: "SOE_ID", value: "qf-aws-win2016-x86_64-1000.1" }])
      component.deploy
    end

    it 'raises error on failed DNS record deployment' do
      component = AwsAutoheal.new(@component_name, @test_data['Input']['Valid'])
      _configure_deploy_mock component

      allow(component).to receive(:deploy_ad_dns_records) .and_raise("Coudn't deploy DNS")

      expect {
        component.deploy
      }.to raise_error(/Failed to deploy DNS records/)
    end
  end
end
