module DbParameterGroupBuilder
  def _process_db_parameter_groups(template: nil, db_parameter_groups: nil)
    db_parameter_groups.each do |name, definition|
      template["Resources"][name] = {
        "Type" => "AWS::RDS::DBParameterGroup",
        "Properties" => {
          "Description" => JsonTools.get(definition, "Properties.Description", "Custom Parameter Group"),
          "Family" => JsonTools.get(definition, "Properties.Family"),
        }
      }

      JsonTools.transfer(definition, "DeletionPolicy", template["Resources"][name], "Delete")
      JsonTools.transfer(definition, "Properties.Parameters", template["Resources"][name])

      template["Outputs"]["#{name}Name"] = {
        "Description" => "DB parameter group name",
        "Value" => { "Ref" => name },
      }
    end
  end
end
