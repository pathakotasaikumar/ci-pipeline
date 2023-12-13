module LogsDestinationBuilder
  # Generates component specific Lambda function name
  # @return [String] Component specific lambda function name
  def _unique_destination_name(name)
    sections = Defaults.sections
    [
      sections[:ams],
      sections[:qda],
      sections[:as],
      sections[:ase],
      sections[:branch],
      sections[:build],
      @component_name,
      name
    ].join('-').gsub(/[^a-zA-Z0-9\-]/, '-')
  end

  # Create AWS::Logs::Destination resource
  # @param template [Hash] Reference to a template
  # @param definitions [Hash] Subscriptions definitions
  # @param role_arn [String] Role arn to be assumed by the Destination against the target
  # @param source_accounts [List] List of source accounts. ie ([01234567890,098765432123])
  def _process_logs_destination(
    template:,
    definitions:,
    role_arn:,
    source_accounts: []
  )

    definitions.each do |name, definition|
      destination_name = _unique_destination_name(name)

      template['Resources'][name] = {
        'Type' => 'AWS::Logs::Destination',
        'Properties' => {
          'DestinationName' => destination_name,
          'RoleArn' => role_arn,
          'TargetArn' => JsonTools.get(definition, 'Properties.TargetArn'),
        }
      }

      destination_policy = {
        'Version' => '2012-10-17',
        'Statement' => [{
          'Effect' => 'Allow',
          'Principal' => { 'AWS' => source_accounts.uniq.compact },
          'Action' => 'logs:*',
          'Resource' => '*'
        }]
      }

      template['Resources'][name]['Properties']['DestinationPolicy'] = JSON.dump(destination_policy)

      template['Outputs']["#{name}Arn"] = {
        'Description' => 'Log Destination ARN',
        'Value' => { 'Fn::GetAtt' => [name, 'Arn'] }
      }
    end
  end
end
