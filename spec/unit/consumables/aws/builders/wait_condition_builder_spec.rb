$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws/builders")
require 'wait_condition_builder'

RSpec.describe WaitConditionBuilder do
  include WaitConditionBuilder

  before(:context) do
  end

  def _get_builder_instance
    instance = DummyClass.new
    instance.extend(WaitConditionBuilder)

    instance
  end

  context '._process_wait_condition' do
    it 'returns template' do
      resource_name = "MyWaitCondition"

      instance = _get_builder_instance
      template = {
        "Resources" => {},
        "Outputs" => {}
      }

      allow(Context).to receive_message_chain('environment.subnet_ids')
        .and_return([
                      "my-private-subnet-id"
                    ])

      instance._process_wait_condition(
        template: template,
        name: resource_name
      )

      expect(template.class).to eq(Hash)

      resources = template["Resources"]
      expect(resources.class).to eq(Hash)

      expect(resources["#{resource_name}"]).to eq({
        "Type" => "AWS::CloudFormation::WaitConditionHandle",
        "Properties" => {},
      })

      expect(resources["#{resource_name}Condition"]).to eq({
        "Type" => "AWS::CloudFormation::WaitCondition",
        "Properties" => {
          "Count" => "1",
          "Handle" => { "Ref" => resource_name },
          "Timeout" => "1800",
        }
      })
    end
  end
end # RSpec.describe
