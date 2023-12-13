# Module builds CloudWatch AWS::Events::Rule
# http://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-events-rule.html#cfn-events-rule-eventpattern

require "util/json_tools"

module EventsRuleBuilder
  # Generates Cloudformation resource for AWS::Events::Rule based on user specified paramters
  # Adds generated resources to supplied
  #
  # @param template [Hash] template definition carried into the module
  # @param definitions [Hash] events rule definitions
  # @param description [String] Optional description for the event rule
  # @param events_role_arn [String] Name of the role to be used for the event execution
  def _process_events_rule(
    template:,
    definitions:,
    events_role_arn: nil,
    description: nil
  )

    definitions.each do |name, definition|
      Context.component.replace_variables(definition)

      # Favor targets parameter if specified over user defined hash
      targets = JsonTools.get(definition, 'Properties.Targets', [])
      raise ArgumentError, "No Targets specified for the CloudWatch events rule - #{name}" if targets.empty?

      # Substitute resource names into the target definition
      targets.each do |target|
        raise ArgumentError, "Each target must be specified as a Hash for #{name} events rule - #{name}" unless target.is_a? Hash

        target_arn = target.fetch('Arn')
        target['Arn'] = case target_arn
                        when Hash
                          raise ArgumentError unless %w(Ref Fn::GetAtt Fn::Join Fn::ImportValue).include? target_arn.keys.first

                          target_arn
                        when String
                          target_arn.start_with?('arn:aws') ? target_arn : { 'Ref' => target_arn }
                        else
                          raise ArgumentError, "Invalid type #{target_arn.class} specified for rule Target Arn"
                        end

        target['RoleArn'] ||= events_role_arn unless events_role_arn.nil?

        target_input = target.fetch('Input', nil)
        if target_input.is_a?(Hash) && !%w(Fn::Join Fn::Sub).include?(target_input.keys.first)
          target['Input'] = target_input.to_json
        elsif target_input.nil?
          # We need to allow no input, as in pass the whole event through
          # The default behaviour in lambda and state machine inserts {} if Properties.Pipeline::EventInput is not set
          # So the only non breaking change we can allow is to set Properties.Pipeline::EventInput as nil (~) in the template
          # which allows us to get to this condition case in order to delete the input key
          target.delete('Input')
        end
      end

      template['Resources'][name] = {
        "Type" => "AWS::Events::Rule",
        "Properties" => {
          "Description" => description || "Cloudwatch event rule - #{name}",
          "Targets" => targets
        }
      }

      JsonTools.transfer(definition, 'Properties.State', template['Resources'][name])
      JsonTools.transfer(definition, 'Properties.ScheduleExpression', template['Resources'][name])
      JsonTools.transfer(definition, 'Properties.EventPattern', template['Resources'][name])
    end
  end
end
