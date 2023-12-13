$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws")
require 'aws_image'
require 'builders/instance_builder'

RSpec.describe AwsImage do
  include InstanceBuilder
  before(:context) do
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))['UnitTest']
    @component_name = @test_data['Input']['ComponentName']
  end

  context '.initialize' do
    it 'initialize without error' do
      AwsImage.new(@component_name, @test_data['Input']['Initialize']['Valid'])
    end
  end

  context '._full_template' do
    it '_full_template calls _default_ou_path' do
      allow(AwsHelper).to receive(:_provisioning_credentials)
      allow(AwsHelper).to receive(:_control_credentials)

      had_default_ou_path_call = false
      expected_arg = {
        ams: Defaults.sections[:ams],
        qda: Defaults.sections[:qda],
        as: Defaults.sections[:as],
        env: Defaults.sections[:env]
      }

      allow(Defaults).to receive(:dns_zone).and_return(Defaults.ad_dns_zone)
      awsInstance = AwsImage.new(@component_name, @test_data['Input']['Initialize']['Valid'])

      allow(awsInstance).to receive(:_process_instance_profile) .and_return({})
      allow(awsInstance).to receive(:_metadata_pre_prepare) .and_return({})
      allow(awsInstance).to receive(:_metadata_pre_deploy) .and_return({})
      allow(awsInstance).to receive(:_metadata_post_deploy) .and_return({})
      allow(awsInstance).to receive(:_metadata_auth) .and_return({})
      allow(awsInstance).to receive(:_process_instance) .and_return({})
      allow(awsInstance).to receive(:_add_recovery_alarm) .and_return({})

      allow(awsInstance).to receive(:_metadata_pre_prepare) .and_return({})
      allow(awsInstance).to receive(:_metadata_bake_post_deploy) .and_return({})
      allow(awsInstance).to receive(:_metadata_auth) .and_return({})

      # _default_ou_path should be hit
      allow(awsInstance).to receive(:_default_ou_path) do |arg1|
        expect(arg1).to eq expected_arg
        had_default_ou_path_call = true
      end

      awsInstance.send :_bake_instance_template
      expect(had_default_ou_path_call).to eq true
    end
  end

  context "deploy" do
    it 'deploy bake instance with image' do
      allow(AwsHelper).to receive(:_provisioning_credentials)
      allow(AwsHelper).to receive(:_control_credentials)

      awsImage = AwsImage.new(@component_name, @test_data['Input']['Initialize']['Valid'])

      soe_details = {
        name: "qf-aws-win2016-x86_64-1000.1",
        id: "ami-1234567",
        tags: [{ key: "AMSID", value: "AMS01" }, { key: "EnterpriseAppID", value: "C031" }, { key: "ApplicationServiceID", value: "01" }],
        description: "soe image description",
        state: "available",
        platform: "rhel"
      }
      image_name = "qf-aws-win2016-x86_64-1000.1"

      image_output = {
        "ImageId" => 'Id',
        "ImageName" => 'qf-aws-win2016-x86_64-1000.1'
      }

      allow(awsImage).to receive_messages(
        :_bake_instance_template => { "Resources" => {}, "Outputs" => {} }
      )

      allow(AwsHelper).to receive(:ec2_get_image_details) .and_return(soe_details)
      expect(TagHelper.get_tag_values(tags: soe_details[:tags], default_value: image_name, tag_key: 'SOE_ID')).to eq([{ key: "SOE_ID", value: "qf-aws-win2016-x86_64-1000.1" }])

      allow(AwsHelper).to receive(:ec2_shutdown_instance_and_create_image) .and_return(image_output)
      allow(awsImage).to receive(:_build_bake_stack)
    end
  end

  context "_build_bake_stack" do
    it 'returns template' do
      allow(AwsHelper).to receive(:_provisioning_credentials)
      allow(AwsHelper).to receive(:_control_credentials)

      component = AwsImage.new(@component_name, @test_data['Input']['Initialize']['Valid'])

      allow(Context).to receive_message_chain("component.variable")
      allow(Context).to receive_message_chain("component.role_name")
      allow(Context).to receive_message_chain("component.set_variables")
      allow(Context).to receive_message_chain("component.sg_id")
      allow(Context).to receive_message_chain("component.stack_id")

      allow(AwsHelper).to receive(:cfn_update_stack)
      allow(AwsHelper).to receive(:cfn_create_stack)
      allow(AwsHelper).to receive(:s3_download_objects)

      allow(component).to receive(:_bake_instance_template)
      allow(TagHelper).to receive(:get_tag_values) .and_return([{ key: "SOE_ID", value: "qf-aws-win2016-x86_64-1000.1" }])
      # normal
      component.send(
        :_build_bake_stack,
        soe_ami_id: '',
        soe_ami_name: '',
        soe_tags: '',
        image_name: '',
        platform: :centos
      )
    end

    it 'raises error on failed stack' do
      allow(AwsHelper).to receive(:_provisioning_credentials)
      allow(AwsHelper).to receive(:_control_credentials)

      component = AwsImage.new(@component_name, @test_data['Input']['Initialize']['Valid'])

      allow(Defaults).to receive(:component_stack_name)
      allow(AwsHelper).to receive(:s3_download_objects)

      allow(Context).to receive_message_chain("component.variable")
      allow(Context).to receive_message_chain("component.role_name")
      allow(Context).to receive_message_chain("component.set_variables")
      allow(Context).to receive_message_chain("component.sg_id")
      allow(Context).to receive_message_chain("component.stack_id")

      allow(component).to receive(:_bake_instance_template)

      allow(TagHelper).to receive(:get_tag_values).and_return([{ key: "SOE_ID", value: "qf-aws-win2016-x86_64-1000.1" }])
      allow(AwsHelper).to receive(:cfn_create_stack).and_raise(ActionError.new('Cannot deploy stacks'))

      expect {
        component.send(
          :_build_bake_stack,
          soe_ami_id: '',
          soe_ami_name: '',
          soe_tags: '',
          image_name: '',
          platform: :centos
        )
      }.to raise_error(RuntimeError, /Failed to create instance bake stack - ActionError/)
    end
  end
end # RSpec.describe
