require 'util/json_tools'

# Module is responsible for generating Amazon MQ Broker Configuration CloudFormation resource
module AmqConfigurationBuilder
  # Generate AWS::AmazonMQ::Configuration resource
  # @param template [Hash] CloudFormation template passed in as reference
  # @param component_name [String] Logical name for associated MQ Broker resource
  # @param amq_configuration [Hash] MQ Broker details parsed from component definition file
  def _process_amq_configuration_builder(
    template: nil,
    component_name: nil,
    amq_configuration: nil
  )
    name, definition = amq_configuration.first
    Context.component.replace_variables(definition)

    amq_configuration_description = "Configuration file for #{name}"

    data_string = JsonTools.get(definition, "Properties.Data").to_s # unless data_string.is_a? String

    data_string = { 'Fn::Base64' => data_string }

    template['Resources'][name] = {
      "Type" => "AWS::AmazonMQ::Configuration",
      "Properties" => {
        "Description" => amq_configuration_description,
        "EngineType" => JsonTools.get(definition, "Properties.EngineType", "ACTIVEMQ"),
        "EngineVersion" => JsonTools.get(definition, "Properties.EngineVersion", nil),
        "Data" => data_string

      }
    }

    resource = template["Resources"][name]

    sections = Defaults.sections

    fq_name = [
      sections[:ams],
      sections[:qda],
      sections[:as],
      sections[:ase],
      sections[:branch],
      component_name,
      name
    ].join('-')

    resource["Properties"]["Name"] = fq_name.gsub(/[^A-Za-z0-9_\-]/, "")[0..150]

    template['Outputs']["#{name}Id"] = {
      'Description' => "#{name} AMQ Configuration Id",
      'Value' => {
        'Ref' => name
      }
    }

    template['Outputs']["#{name}Revision"] = {
      'Description' => "#{name} AMQ Configuration Revision",
      'Value' => {
        'Fn::GetAtt' => [
          name,
          'Revision'
        ]
      }
    }

    template['Outputs']["#{name}Arn"] = {
      'Description' => "#{name} AMQ Configuration Arn",
      'Value' => {
        'Fn::GetAtt' => [
          name,
          'Arn'
        ]
      }
    }
  end
end
