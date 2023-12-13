require "util/json_tools"

module KmsKeyBuilder
  def _process_kms_key(
    template: nil,
    dr_account_id: nil,
    nonp_account_id: nil,
    kms_key_definition: nil,
    environment: nil
  )
    name, definition = kms_key_definition.first

    template["Resources"][name] = {
      "Type" => "AWS::KMS::Key",
      "Properties" => {
        "Description" => JsonTools.get(definition, "Properties.Description", "KMS key #{name}"),
        "EnableKeyRotation" => JsonTools.get(definition, "Properties.EnableKeyRotation", true),
        "KeyPolicy" => {
          "Version" => "2012-10-17",
          "Id" => "DefaultOwnAccount",
          "Statement" => [
            {
              "Sid" => "Allow use of the key by resources",
              "Effect" => "Allow",
              "Principal" => { "AWS" => { "Fn::Join" => ["", ["arn:aws:iam::", { "Ref" => "AWS::AccountId" }, ":root"]] } },
              "Action" => [
                "kms:*"
              ],
              "Resource" => "*"
            },
            {
              "Sid" => "Do not allow anyone to schedule key for deletion",
              "Effect" => "Deny",
              "Principal" => {
                "AWS" => "*"
              },
              "Action" => "kms:ScheduleKeyDeletion",
              "Resource" => "*"
            },
            {
              "Sid" => "Allow DR Account to decrypt resources",
              "Effect" => "Allow",
              "Principal" => {
                "AWS" => "arn:aws:iam::#{dr_account_id}:root"
              },
              "Action" => [
                "kms:Decrypt",
                "kms:ReEncryptFrom",
                "kms:DescribeKey",
                "kms:GenerateDataKeyWithoutPlaintext",
                "kms:CreateGrant",
                "kms:ReEncryptTo"
              ],
              "Resource" => "*"
            }
          ]
        }
      }
    }

    if environment.downcase == "prod"
      template["Resources"][name]["Properties"]["KeyPolicy"] ["Statement"] << {
        "Sid" => "Allow Non Prod Account to decrypt resources",
        "Effect" => "Allow",
        "Principal" => {
          "AWS" => "arn:aws:iam::#{nonp_account_id}:root"
        },
        "Action" => [
          "kms:Decrypt",
          "kms:ReEncryptFrom",
          "kms:DescribeKey",
          "kms:GenerateDataKeyWithoutPlaintext",
          "kms:CreateGrant",
          "kms:ReEncryptTo"
        ],
        "Resource" => "*"
      }
    end

    template["Outputs"]["#{name}Name"] = {
      "Description" => "KMS key name",
      "Value" => { "Ref" => name },
    }

    template["Outputs"]["#{name}Arn"] = {
      "Description" => "KMS key ARN",
      "Value" => { "Fn::Join" => ["", ["arn:aws:kms:", { "Ref" => "AWS::Region" }, ":", { "Ref" => "AWS::AccountId" }, ":key/", { "Ref" => name }]] }
    }
  end
end
