require "util/json_tools"

# Module responsible for building AWS::CloudWatch::Alarm resource
# http://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-properties-cw-alarm.html
module AlarmBuilder
  # Take reference to a template and build AWS::CloudWatch::Alarm resource
  # @param template [Hash] Reference to a template
  # @param alarm_definitions [Hash] List of alarm specifications
  def _process_alarms(
    template: nil,
    alarm_definitions: []
  )
    alarm_definitions.each do |name, definition|
      template["Resources"][name] = {
        "Type" => "AWS::CloudWatch::Alarm",
        "Properties" => {
          "ActionsEnabled" => JsonTools.get(definition, "Properties.ActionsEnabled", true),
          "AlarmDescription" => JsonTools.get(definition, "Properties.AlarmDescription", "Alarm #{name}"),
          "ComparisonOperator" => JsonTools.get(definition, "Properties.ComparisonOperator"),
          "EvaluationPeriods" => JsonTools.get(definition, "Properties.EvaluationPeriods"),
          "MetricName" => JsonTools.get(definition, "Properties.MetricName"),
          "Namespace" => JsonTools.get(definition, "Properties.Namespace"),
          "Period" => JsonTools.get(definition, "Properties.Period"),
          "Statistic" => JsonTools.get(definition, "Properties.Statistic"),
          "Threshold" => JsonTools.get(definition, "Properties.Threshold")
        }
      }

      resource = template["Resources"][name]

      alarm_actions = Array(JsonTools.get(definition, "Properties.AlarmActions", []))
      alarm_actions = alarm_actions.map do |action|
        next action.is_a?(String) ? { "Ref" => action } : action
      end

      resource["Properties"]["AlarmActions"] = alarm_actions unless alarm_actions.empty?

      insufficient_data_actions = Array(JsonTools.get(definition, "Properties.InsufficientDataActions", []))
      insufficient_data_actions = insufficient_data_actions.map do |action|
        next action.is_a?(String) ? { "Ref" => action } : action
      end

      resource["Properties"]["InsufficientDataActions"] = insufficient_data_actions unless insufficient_data_actions.empty?

      namespace = JsonTools.get(resource, "Properties.Namespace")
      if namespace == "QCP/Custom"
        dimensions = JsonTools.get(definition, "Properties.Dimensions", [])

        # Only allow (and require) the user to specify the Component dimension
        if !dimensions.is_a? Array || dimensions.size != 1 || dimensions.first["Name"] != "Component"
          raise "Dimension property must specify a single dimension - Component"
        elsif !dimensions[0]["Value"].is_a? String || dimensions.first["Value"].empty?
          raise "Value for dimension \"Component\" must be a string containing target component name"
        end

        component_name = dimensions.first["Value"]
        component_name = @component_name if component_name == "@self"

        resource["Properties"]["Dimensions"] = _custom_dimensions(
          component_name: component_name
        )

      elsif namespace.start_with? "AWS/"
        resource["Properties"]["Dimensions"] = []

        dimensions = JsonTools.get(definition, "Properties.Dimensions")
        unless dimensions.is_a? Array
          raise "The AWS::CloudWatch::Alarm Dimensions property must be an array"
        end

        dimensions.each do |user_dimension|
          dimension_name = JsonTools.get(user_dimension, "Name")
          dimension_value = JsonTools.get(user_dimension, "Value")

          # Validate and resolve dimension
          valid_dimension = false

          case dimension_value
          when Hash
            # Dimension must be a Ref or Fn::GetAtt or Fn::ImportValue
            if dimension_value.keys.length == 1 && %w(Ref Fn::GetAtt Fn::ImportValue).include?(dimension_value.keys.first)
              valid_dimension = true
            end
          when String
            # Dimension must be an alias
            if dimension_value.start_with? "@"
              # Resolve alias variable reference
              valid_dimension = true
              dimension_value = Context.component.replace_variables(dimension_value)
            end
          end

          unless valid_dimension
            raise "Invalid value for Dimension #{dimension_name.inspect} -" \
                  "All dimension values must be a Ref, Fn::GetAtt, Fn::ImportValue, or an @ alias"
          end

          resource["Properties"]["Dimensions"] << {
            "Name" => dimension_name,
            "Value" => dimension_value
          }
        end
      else
        raise "Invalid namespace #{namespace.inspect} - " \
              "namespace must start with AWS/ or be QCP/Custom"
      end

      template["Outputs"]["#{name}Name"] = {
        "Description" => "Alarm name",
        "Value" => { "Ref" => name }
      }
    end
  end

  private

  # Returns a list of key value pairs for dimensions
  # @param component_name [String] Component name
  # @return [Array] List of key value pairs for CloudWatch dimensions
  def _custom_dimensions(component_name: nil)
    [
      {
        "Name" => "AMSID",
        "Value" => Defaults.sections[:ams]
      },
      {
        "Name" => "EnterpriseAppID",
        "Value" => Defaults.sections[:qda]
      },
      {
        "Name" => "ApplicationServiceID",
        "Value" => Defaults.sections[:as]
      },
      {
        "Name" => "Environment",
        "Value" => Defaults.sections[:ase]
      },
      {
        "Name" => "Branch",
        "Value" => Defaults.sections[:branch]
      },
      {
        "Name" => "Build",
        "Value" => Context.component.build_number(component_name)
      },
      {
        "Name" => "Component",
        "Value" => component_name
      }
    ]
  end
end
