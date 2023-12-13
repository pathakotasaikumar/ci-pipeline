$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws/builders")
require 'network_interface_builder'

RSpec.describe NetworkInterfaceBuilder do
  include NetworkInterfaceBuilder

  before(:context) do
  end

  def _get_builder_instance
    instance = DummyClass.new
    instance.extend(NetworkInterfaceBuilder)

    instance
  end

  context '._process_network_interface' do
    it 'returns template' do
      resource_name = "MyInterface"

      instance = _get_builder_instance
      template = {
        "Resources" => {},
        "Outputs" => {}
      }

      allow(Context).to receive_message_chain('environment.subnet_ids')
        .and_return([
                      "my-private-subnet-id"
                    ])

      instance._process_network_interface(
        template: template,
        network_interface_definition: {
          resource_name => {
            "Properties" => {
              "SubnetId" => "@a-private",
              "SourceDestCheck" => "check"
            }
          }
        },
        security_group_ids: {}
      )

      expect(template.class).to eq(Hash)

      resources = template["Resources"]
      outputs = template["Outputs"]

      expect(resources.class).to eq(Hash)
      expect(outputs.class).to eq(Hash)

      expect(outputs["#{resource_name}Id"]).to eq({
        "Description" => "ENI id",
        "Value" => { "Ref" => resource_name },
      })

      expect(outputs["#{resource_name}Arn"]).to eq({
        "Description" => "ENI ARN",
        "Value" => { "Fn::Join" => ["/", [{ "Fn::Join" => [":", ["arn:aws:ec2", { "Ref" => "AWS::Region" }, { "Ref" => "AWS::AccountId" }, "network-interface"]] }, { "Ref" => resource_name }]] }
      })

      expect(outputs["#{resource_name}PrimaryPrivateIpAddress"]).to eq({
        "Description" => "Primary private IP address",
        "Value" => { "Fn::GetAtt" => [resource_name, "PrimaryPrivateIpAddress"] },
      })

      expect(outputs["#{resource_name}SecondaryPrivateIpAddresses"]).to eq({
        "Description" => "Primary private IP address",
        "Value" => { "Fn::Join" => [",", { "Fn::GetAtt" => [resource_name, "SecondaryPrivateIpAddresses"] }] },
      })
    end
  end
end # RSpec.describe
