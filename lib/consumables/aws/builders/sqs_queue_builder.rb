require "util/json_tools"

module SqsQueueBuilder
  def _process_queue(
    template: nil,
    queue_definition: nil
  )

    name, definition = queue_definition.first
    Context.component.replace_variables(definition)

    template["Resources"][name] = {
      "Type" => "AWS::SQS::Queue",
      "Properties" => {
        "DelaySeconds" => JsonTools.get(definition, "Properties.DelaySeconds", 0),
        "MaximumMessageSize" => JsonTools.get(definition, "Properties.MaximumMessageSize", 262144),
        "MessageRetentionPeriod" => JsonTools.get(definition, "Properties.MessageRetentionPeriod", 345600),
        "ReceiveMessageWaitTimeSeconds" => JsonTools.get(definition, "Properties.ReceiveMessageWaitTimeSeconds", 0),
        "VisibilityTimeout" => JsonTools.get(definition, "Properties.VisibilityTimeout", 30),
      }
    }

    resource = template["Resources"][name]

    # Add optional properties for SQS FIFO
    JsonTools.transfer(definition, "Properties.ContentBasedDeduplication", resource)
    JsonTools.transfer(definition, "Properties.FifoQueue", resource)

    # Set optional redrive policy
    redrive_policy = JsonTools.get(definition, "Properties.RedrivePolicy", nil)

    unless redrive_policy.nil? || redrive_policy.empty?

      dead_letter_queue_arn = JsonTools.get(definition, "Properties.RedrivePolicy.deadLetterTargetArn")

      unless dead_letter_queue_arn.start_with? "arn:aws:sqs:#{Context.environment.region}:#{Context.environment.account_id}:"
        raise "Missing valid ARN for deadLetterTargetArn. Ensure target SQS component is built in the previous stage"
      end

      resource["Properties"]["RedrivePolicy"] = {
        "deadLetterTargetArn" => dead_letter_queue_arn,
        "maxReceiveCount" => JsonTools.get(definition, "Properties.RedrivePolicy.maxReceiveCount")
      }
    end

    # Set outputs
    template["Outputs"]["#{name}Endpoint"] = {
      "Description" => "Queue endpoint URL",
      "Value" => { "Ref" => name }
    }
    template["Outputs"]["#{name}QueueName"] = {
      "Description" => "Queue name",
      "Value" => { "Fn::GetAtt" => [name, "QueueName"] }
    }
    template["Outputs"]["#{name}Arn"] = {
      "Description" => "Queue ARN",
      "Value" => { "Fn::GetAtt" => [name, "Arn"] }
    }
  end

  # Adds SQS queue policy resource to the CloudFormation template
  # @param template [Hash] Reference to a template
  # @param definitions [Hash] User defined SQS policy definitions
  def _process_sqs_queue_policy(
    template: nil,
    definitions: nil
  )
    name, definition = definitions.first
    Context.component.replace_variables(definition)

    template["Resources"][name] = {
      "Type" => "AWS::SQS::QueuePolicy",
      "Properties" => {
        "PolicyDocument" => JsonTools.get(definition, "Properties.PolicyDocument"),
        "Queues" => JsonTools.get(definition, "Properties.Queues")
      }
    }
  end
end
