require_relative "pipeline_autoscaling_action_builder"

# Module functions as a proxy for PipelineAutoscalingAction
# Generates autoscaling lifecycleaction for handling ENI attachment to autoscaled instances
module NetworkAttachmentBuilder
  include PipelineAutoscalingActionBuilder

  # @param template [Hash] CloudFormation template passed in as reference
  # @param autoscaling_group_name [String] unique autoscaling group name
  # @param execution_role_arn [String] name of the role to be assigned to lambda executor
  # @param notification_role_arn [String] name of the IAM role to be assigned to autoscaling group for notifications
  # @param network_attachments [Array] list of key value pairs of eni ids and device index values for attachment
  def _process_network_attachments(
    template: nil,
    autoscaling_group_name: nil,
    execution_role_arn: nil,
    notification_role_arn: nil,
    network_attachments: nil
  )

    _process_pipeline_autoscaling_action(
      template: template,
      action_name: "NetworkAttachment",
      autoscaling_group_name: autoscaling_group_name,
      execution_role_arn: execution_role_arn,
      notification_role_arn: notification_role_arn,
      notification_metadata: network_attachments.to_json,
      lambda_code: "#{__dir__}/../aws_autoheal/attach_eni.py"
    )
  end

  # Parses Pipeline::Autoheal::NetworkAttachment resource specified in YAML
  # @param resource [Hash] subset of the component YAML definition for Pipeline::Autoheal::NetworkInterfaceAttachment
  # @return [Array] list of key value pairs for eni ids and device index values for attachment
  def _parse_network_attachments(resource)
    attachments = []
    resource.each do |name, definition|
      definition = Context.component.replace_variables(definition)

      interface = JsonTools.get(definition, "Properties.NetworkInterfaceId", nil).to_s
      device = JsonTools.get(definition, "Properties.DeviceIndex", nil).to_s

      unless device =~ /^[1-9]{1}$/ && interface =~ /^eni-[a-z0-9]+$/
        raise ArgumentError, "Invalid value specified for device #{device} or interface #{interface}"
      end

      attachments << { "NetworkInterfaceId" => interface, "DeviceIndex" => device }
    end
    attachments
  end

  # @return [Array] list of security rules required for the lambda executor
  def _network_attachment_security_rules(
    component_name: nil,
    execution_role_name: nil
  )

    [
      # Allow attachment of volumes
      IamSecurityRule.new(
        roles: "#{component_name}.#{execution_role_name}",
        actions: %w(ec2:AttachNetworkInterface),
        resources: %w(*)
      ),
      IamSecurityRule.new(
        roles: "#{component_name}.#{execution_role_name}",
        actions: %w(
          logs:CreateLogStream
          logs:PutLogEvents
        ),
        resources: %w(arn:aws:logs:*:*:*)
      )
    ]
  end
end
