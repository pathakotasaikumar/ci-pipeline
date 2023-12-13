$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws/builders")
require 'db_cluster_parameter_group_builder'

RSpec.describe DbClusterParameterGroupBuilder do
  include DbClusterParameterGroupBuilder

  before(:context) do
  end

  def _get_builder_instance
    instance = DummyClass.new
    instance.extend(DbClusterParameterGroupBuilder)

    instance
  end

  context '._process_db_cluster_parameter_group' do
    it 'returns template' do
      resource_name = "MyDb"

      instance = _get_builder_instance
      template = {
        "Resources" => {},
        "Outputs" => {}
      }

      allow(Context).to receive_message_chain('environment.subnet_ids')
        .and_return([
                      "my-private-subnet-id"
                    ])

      instance._process_db_cluster_parameter_group(
        template: template,
        db_cluster_parameter_group: {
          resource_name => {
            "Properties" => {
              "Family" => 'MyFamily',
              "Parameters" => {
                "P1" => "V1"
              }
            }
          }
        }
      )

      expect(template.class).to eq(Hash)

      resources = template["Resources"]
      outputs = template["Outputs"]

      expect(resources.class).to eq(Hash)
      expect(outputs.class).to eq(Hash)

      expect(outputs["#{resource_name}"]).to eq({
        'Description' => 'Customer Cluster Parameter Group',
        'Value' => { 'Ref' => resource_name },
      })

      expect(resources["#{resource_name}"]).to eq({
        'Type' => 'AWS::RDS::DBClusterParameterGroup',
        'DeletionPolicy' => 'Delete',
        'Properties' => {
          'Description' => 'Custom Parameter Group',
          'Family' => 'MyFamily',
          "Parameters" => {
            "P1" => "V1"
          }
        }
      })
    end
  end
end # RSpec.describe
