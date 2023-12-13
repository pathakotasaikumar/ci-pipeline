# Module responsible for construction AWS::SNS::Topic template
module SnsTopicBuilder
  # @param template [Hash] reference to template carried into the module
  # @param definitions [Hash] Hash representing SNS topic properties
  def _process_sns_topic(
    template:,
    definitions:
  )
    definitions.each do |name, definition|
      subscriptions = JsonTools.get(definition, 'Properties.Subscriptions', nil)

      template["Resources"][name] = {
        "Type" => "AWS::SNS::Topic",
        "Properties" => {}
      }

      unless subscriptions.nil? || subscriptions.empty?
        template["Resources"][name]['Properties']['Subscription'] = subscriptions
      end

      template["Outputs"]["#{name}Name"] = {
        "Description" => "Topic Name",
        "Value" => { "Fn::GetAtt" => [name, "TopicName"] }
      }

      template["Outputs"]["#{name}Arn"] = {
        "Description" => "Topic Arn",
        "Value" => { "Ref" => name }
      }
    end
  end

  # Create AWS::SNS::Subscription resource
  # @param template [Hash] Reference to a template
  # @param definitions [Hash] Subscriptions definitions
  def _process_sns_subscription(
    template:,
    definitions:
  )
    definitions.each do |name, definition|
      delivery_policy = JsonTools.get(definition, 'Properties.DeliveryPolicy', {})
      filter_policy = JsonTools.get(definition, 'Properties.FilterPolicy', {})

      template["Resources"][name] = {
        "Type" => "AWS::SNS::Subscription",
        "Properties" => {
          'Protocol' => JsonTools.get(definition, 'Properties.Protocol'),
          'TopicArn' => JsonTools.get(definition, 'Properties.TopicArn'),
          'DeliveryPolicy' => delivery_policy,
          'FilterPolicy' => filter_policy
        }
      }
      endpoint = JsonTools.get(definition, 'Properties.Endpoint')
      template['Resources'][name]['Properties']['Endpoint'] = endpoint unless endpoint.nil?
    end
  end

  # Adds SNS topic policy resource to the cloudformation template
  # @param template [Hash] Reference to a template
  # @param source_accounts [List] List of account numbers which are delegated Publish rights to the topic
  # @param definitions [Hash] User defined SNS Topic definitions
  def _process_sns_topic_policy(
    template:,
    source_accounts:,
    definitions:
  )
    definitions.each do |name, definition|
      topic_policy = {
        'Version' => '2012-10-17',
        'Statement' => [{
          'Sid' => 'SourceAccounts',
          'Effect' => 'Allow',
          'Principal' => { 'AWS' => source_accounts.uniq.compact },
          'Action' => 'sns:Publish',
          'Resource' => '*'
        }]
      }

      template['Resources'][name] = {
        'Type' => 'AWS::SNS::TopicPolicy',
        'Properties' => {
          'PolicyDocument' => topic_policy.to_json,
          'Topics' => JsonTools.get(definition, 'Properties.Topics')
        }
      }
    end
  end
end
