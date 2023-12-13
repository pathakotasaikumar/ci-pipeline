require_relative "aws/builders/kms_key_builder"

class PipelineKmsKey
  extend KmsKeyBuilder

  def self.deploy
    # Try to load the secrets key ARN from cache
    key_arn = Context.kms.secrets_key_arn
    return unless key_arn.nil?

    # Try to find the secrets key ARN from an existing stack
    stack_name = Defaults.kms_stack_name
    stack_id = AwsHelper.cfn_stack_exists(stack_name)
    if stack_id.nil?
      Log.info "Creating a new secrets KMS key"
      template = _build_template
      begin
        # Create KMS key stack
        tags = Defaults.get_tags("Kms", :env)
        outputs = AwsHelper.cfn_create_stack(stack_name: stack_name, template: template, tags: tags)
        Context.kms.set_secrets_details(stack_id, outputs["KeyArn"])
        raise "Stack did not output a KMS key ARN" if outputs["KeyArn"].nil?

        # Create key alias
        AwsHelper.kms_create_alias(Context.kms.secrets_key_arn, Defaults.kms_secrets_key_alias)
      rescue ActionError => e
        raise "Failed to create KMS stack - #{e}"
      end
    else
      Log.info "Using existing KMS key"
      begin
        outputs = AwsHelper.cfn_get_stack_outputs(stack_id)
        arn = outputs["KeyArn"] || outputs["Arn"]
        raise "Stack did not output a KMS key ARN" if arn.nil?

        Context.kms.set_secrets_details(stack_id, arn)

        # Create/Update key alias
        AwsHelper.kms_create_alias(Context.kms.secrets_key_arn, Defaults.kms_secrets_key_alias)
      rescue => e
        raise "An error occurred retrieving the existing KMS key ARN - #{e}"
      end
    end
  end

  def self._build_template
    sections = Defaults.sections
    definition = {
      "Type" => "AWS::KMS::Key",
      "Properties" => {
        "Description" => "KMS key for application service #{sections[:ams]}-#{sections[:qda]}-#{sections[:as]}-#{sections[:env]}",
        "EnableKeyRotation" => true,
      }
    }

    template = { "Resources" => {}, "Outputs" => {} }
    _process_kms_key(
      template: template,
      dr_account_id: Context.environment.dr_account_id,
      nonp_account_id: Context.environment.nonp_account_id,
      kms_key_definition: { "Key" => definition },
      environment: Defaults.sections[:env],
    )

    return template
  end
end
