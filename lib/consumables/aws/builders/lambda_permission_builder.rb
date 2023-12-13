# Module responsible for construction AWS::Lambda::Permission template
module LambdaPermissionBuilder
  # @param template [Hash] template carried into the function
  # @param permissions [Hash] Definition for lambda permissions
  def _process_lambda_permission(
    template:,
    permissions:
  )

    permissions.each do |name, definition|
      template["Resources"][name] = {
        "Type" => "AWS::Lambda::Permission",
        "Properties" => {
          "Action" => JsonTools.get(definition, 'Properties.Action'),
          "FunctionName" => JsonTools.get(definition, 'Properties.FunctionName'),
          "Principal" => JsonTools.get(definition, 'Properties.Principal'),
        }
      }
      JsonTools.transfer(definition, 'Properties.SourceAccount', template["Resources"][name])
      JsonTools.transfer(definition, 'Properties.SourceArn', template["Resources"][name])
    end
  end
end
