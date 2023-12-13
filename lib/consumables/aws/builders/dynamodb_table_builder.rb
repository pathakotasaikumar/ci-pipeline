require "util/json_tools"

module DynamoDbTableBuilder
  def _process_dynamodb_table(
    template: nil,
    table_definition: nil,
    component_name: nil,
    billing_mode: nil
  )

    name, definition = table_definition.first
    if billing_mode.eql? "PAY_PER_REQUEST"
      template["Resources"][name] = {
        "Type" => "AWS::DynamoDB::Table",
        "Properties" => {
          "AttributeDefinitions" => JsonTools.get(definition, "Properties.AttributeDefinitions"),
          "KeySchema" => JsonTools.get(definition, "Properties.KeySchema"),
          "BillingMode" => JsonTools.get(definition, "Properties.BillingMode")
        }
      }
    else
      template["Resources"][name] = {
        "Type" => "AWS::DynamoDB::Table",
        "Properties" => {
          "AttributeDefinitions" => JsonTools.get(definition, "Properties.AttributeDefinitions"),
          "KeySchema" => JsonTools.get(definition, "Properties.KeySchema")
        }
      }
    end
    resource = template["Resources"][name]

    # Set the table name
    table_name = JsonTools.get(definition, "Properties.TableName", name)
    sections = Defaults.sections

    # Generate unique table name based on component
    fq_name = [
      sections[:ams],
      sections[:qda],
      sections[:as],
      sections[:ase],
      sections[:branch],
      sections[:build],
      component_name,
      table_name
    ].join('-')

    resource["Properties"]["TableName"] = fq_name.gsub(/[^A-Za-z0-9_\-]/, "")[0..128]

    if resource["Properties"].has_key? "BillingMode" and resource["Properties"]["BillingMode"].eql? "PAY_PER_REQUEST"
      JsonTools.transfer(definition, "Properties.BillingMode", resource, 1)
    elsif resource["Properties"].has_key? "BillingMode" and resource["Properties"]["BillingMode"].eql? "PROVISIONED"
      JsonTools.transfer(definition, "Properties.ProvisionedThroughput.ReadCapacityUnits", resource, 1)
      JsonTools.transfer(definition, "Properties.ProvisionedThroughput.WriteCapacityUnits", resource, 1)
    else
      JsonTools.transfer(definition, "Properties.ProvisionedThroughput.ReadCapacityUnits", resource, 1)
      JsonTools.transfer(definition, "Properties.ProvisionedThroughput.WriteCapacityUnits", resource, 1)
    end
    JsonTools.transfer(definition, "Properties.GlobalSecondaryIndexes", resource)
    JsonTools.transfer(definition, "Properties.LocalSecondaryIndexes", resource)
    JsonTools.transfer(definition, "Properties.StreamSpecification", resource)
    JsonTools.transfer(definition, "Properties.TimeToLiveSpecification", resource)

    template["Outputs"]["#{name}Arn"] = {
      "Description" => "Table ARN",
      "Value" => {
        "Fn::Join" => ["", [
          "arn:aws:dynamodb:",
          { "Ref" => "AWS::Region" },
          ":",
          { "Ref" => "AWS::AccountId" },
          ":table/",
          { "Ref" => name }
        ]]
      }
    }

    template["Outputs"]["#{name}Name"] = {
      "Description" => "Table Name",
      "Value" => { "Ref" => name },
    }

    unless JsonTools.get(resource, "Properties.StreamSpecification.StreamViewType", nil).nil?
      template["Outputs"]["#{name}StreamArn"] = {
        "Description" => "Table Stream ARN",
        "Value" => { "Fn::GetAtt" => [name, "StreamArn"] },
      }
    end
  end
end
