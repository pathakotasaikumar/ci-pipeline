require_relative 'lambda_permission_builder'

# Module responsible for construction AWS::Logs::SubscriptionFilter template
module LogsSubscriptionFilterBuilder
  include LambdaPermissionBuilder

  # @param template [Hash] reference to template carried into the module
  # @param definitions [Hash] Hash representing Logs LogGroup properties
  # @param log_group [String] String representing a Log group name or CFN Resource reference
  def _process_logs_subscription_filter(
    template:,
    log_group:,
    definitions:
  )

    definitions.each do |name, definition|
      destination_arn = JsonTools.get(definition, 'Properties.DestinationArn')
      case destination_arn
      when /@[\w-]+\.[\w-]+/
        destination_arn = Context.component.replace_variables(destination_arn)
      when /(.*\.#{Defaults.ad_dns_zone}|.*\.#{Defaults.r53_dns_zone})/
        destination_arn = Defaults.txt_by_dns(destination_arn)
      else
        Log.debug "Using destination ARN: #{destination_arn}"
      end

      if destination_arn.nil? || destination_arn.empty?
        raise "Unable to resolve logs destination reference #{destination_arn}"
      end

      if destination_arn.start_with?('arn:aws:lambda')
        _process_lambda_permission(
          template: template,
          permissions: {
            "#{name}LambdaPermission" => {
              "Properties" => {
                "Action" => "lambda:InvokeFunction",
                "FunctionName" => destination_arn,
                "Principal" => { "Fn::Sub" => "logs.${AWS::Region}.amazonaws.com" },
                "SourceArn" => {
                  "Fn::Sub" => [
                    "arn:aws:logs:${AWS::Region}:${AWS::AccountId}:log-group:${log_group}:*",
                    {
                      "log_group" => JsonTools.get(definition, 'Properties.LogGroupName', log_group)
                    }
                  ]
                }
              }
            }
          }
        )
      end
      
      if destination_arn.start_with?('arn:aws:lambda')
        template["Resources"][name] = {
        "Type" => "AWS::Logs::SubscriptionFilter",
        "DependsOn" => "#{name}LambdaPermission",
        "Properties" => {
          "DestinationArn" => destination_arn,
          "FilterPattern" => JsonTools.get(definition, 'Properties.FilterPattern', ''),
          "LogGroupName" => JsonTools.get(definition, 'Properties.LogGroupName', log_group),
        }
      }
      else
        template["Resources"][name] = {
        "Type" => "AWS::Logs::SubscriptionFilter",
        "Properties" => {
          "DestinationArn" => destination_arn,
          "FilterPattern" => JsonTools.get(definition, 'Properties.FilterPattern', ''),
          "LogGroupName" => JsonTools.get(definition, 'Properties.LogGroupName', log_group),
        }
        }
      end
    end
  end
end
