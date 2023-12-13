$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws")
require 'builders/pipeline_autoscaling_action_builder'
require 'json'

RSpec.describe PipelineAutoscalingActionBuilder do
  include PipelineAutoscalingActionBuilder

  @component_name = "autoheal"
  test_data = YAML.load_file "#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"
  test_output = test_data['UnitTest']['Output']
  secret_test_output = test_data['UnitTest']['SecretManagementOutput']

  Context.environment.set_variables({ "aws_account_id" => "11111111111111" })
  Context.component.set_variables("volume1", { "MyVolumeId" => "vol-123456789" })
  Context.component.set_variables("volume2", { "MyVolumeId" => "vol-123456780" })

  context '_process_pipeline_autoscaling_action' do
    it "retruns template for volume attachment resources" do
      template = { "Resources" => {}, "Outputs" => {} }
      test_input = {
        template: template,
        action_name: "VolumeAttachment",
        autoscaling_group_name: "AutoscalingGroup",
        execution_role_arn: "arn:aws:iam:ap-southeast-2:111111111111:role/LambdaExecutionRole",
        notification_role_arn: "arn:aws:ap-southeast-2:111111111111:autoscaling:lifecyclehook",
        notification_metadata: "[{\"Volume\"=>\"vol-123456789\",\"Device\"=>\"/dev/xvdm1\"}]",
        lambda_code: "#{BASE_DIR}/lib/consumables/aws/aws_autoheal/attach_volume.py"
      }

      allow(Context).to receive_message_chain('kms.secrets_key_arn')
        .and_return 'arn:aws:kms:ap-southeast-2:123456789012:key/12345678-1234-1234-1234-123456789012'

      _process_pipeline_autoscaling_action(**test_input)
      # Log.debug YAML.dump(template)
      # Log.debug YAML.dump(test_output)
      template['Resources']['VolumeAttachmentLambda']['Properties'].delete('Code')
      expect(template).to eq test_output
    end
    it "retruns template for secret management attachment resources" do
      template = { "Resources" => {}, "Outputs" => {} }
      test_input = {
        template: template,
        action_name: "SecretManagement",
        autoscaling_group_name: "AutoscalingGroup",
        execution_role_arn: "arn:aws:iam:ap-southeast-2:111111111111:role/LambdaSecretManagementExecutionRole",
        notification_role_arn: "arn:aws:ap-southeast-2:111111111111:autoscaling:lifecyclehook",
        notification_metadata: "[{\"ams\"=>\"ams01\",\"qda\"=>\"c031\",\"as\"=>\"01\",\"ase\"=>\"dev\"}]",
        lambda_code: "#{BASE_DIR}/lib/consumables/aws/common/platform_secret_management.py",
        heartbeat_timeout: '240',
      }
      allow(Context).to receive_message_chain('kms.secrets_key_arn')
        .and_return 'arn:aws:kms:ap-southeast-2:123456789012:key/12345678-1234-1234-1234-123456789012'

      _process_pipeline_autoscaling_action(**test_input)
      # Log.debug YAML.dump(template)
      # Log.debug YAML.dump(test_output)
      template['Resources']['SecretManagementLambda']['Properties'].delete('Code')
      expect(template).to eq secret_test_output
    end
  end
end # RSpec.describe
