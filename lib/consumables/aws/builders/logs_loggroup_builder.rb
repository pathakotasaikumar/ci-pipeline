# Module responsible for construction AWS::Logs::LogGroup template
module LogsLoggroupBuilder
  # @param template [Hash] reference to template carried into the module
  # @param definitions [Hash] Hash representing Logs LogGroup properties
  def _process_logs_loggroup(
    template:,
    definitions:
  )
    definitions.each do |name, definition|
      template["Resources"][name] = {
        "Type" => "AWS::Logs::LogGroup",
        "Properties" => {}
      }

      JsonTools.transfer(definition, "Properties.LogGroupName", template["Resources"][name])
      JsonTools.transfer(definition, "Properties.RetentionInDays", template["Resources"][name])

      template["Outputs"]["#{name}Arn"] = {
        "Description" => "#{name} LogGroup ARN",
        "Value" => { "Fn::GetAtt" => [name, "Arn"] }
      }

      template["Outputs"]["#{name}Name"] = {
        "Description" => "#{name} LogGroup Name",
        "Value" => { "Ref" => name }
      }
    end
  end
end
