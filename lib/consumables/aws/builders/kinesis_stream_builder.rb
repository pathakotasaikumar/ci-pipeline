require "util/json_tools"

module KinesisStreamBuilder
  def _process_kinesis_stream(
    template: nil,
    stream: nil,
    component_name: nil
  )
    name, definition = stream.first
    stream_enc = JsonTools.get(definition, "Properties.StreamEncryption", nil)
    key_id = (stream_enc.nil?) ? Context.kms.secrets_key_arn : stream_enc["KeyId"]
    template["Resources"][name] = {
      "Type" => "AWS::Kinesis::Stream",
      "Properties" => {
        "ShardCount" => JsonTools.get(definition, "Properties.ShardCount"),
        "StreamEncryption" => {
          "EncryptionType" => "KMS",
          "KeyId" => key_id
        }
      }
    }
    resource = template["Resources"][name]

    # Set the stream name
    sections = Defaults.sections
    resource["Properties"]["Name"] = "#{sections[:ams]}-#{sections[:qda]}-#{sections[:as]}-#{sections[:ase]}-#{sections[:branch]}-#{sections[:build]}-#{component_name}-#{name}".gsub(/[^A-Za-z0-9-]/, '-')[0..128]

    template["Outputs"]["#{name}Arn"] = {
      "Description" => "Kinesis stream ARN",
      "Value" => { "Fn::GetAtt" => [name, "Arn"] },
    }

    template["Outputs"]["#{name}Name"] = {
      "Description" => "Kinesis stream name",
      "Value" => { "Ref" => name }
    }
  end
end
