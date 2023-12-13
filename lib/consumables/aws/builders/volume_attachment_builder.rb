require_relative "pipeline_autoscaling_action_builder"

# Module functions as a proxy for PipelineAutoscalingAction
# Generates autoscaling lifecycle action for handling volume attachment to autoscaling instances
module VolumeAttachmentBuilder
  include PipelineAutoscalingActionBuilder

  # @param template [Hash] reference to CloudFormation template
  # @param autoscaling_group_name [String] unique autoscaling group name
  # @param execution_role_arn [String] arn for the IAM role to be assigned to lambda executor
  # @param notification_role_arn [String] arn for the IAM role to be assigned to autoscaling group for notifications
  # @param volume_attachments [Array] list of key value pairs of volume ids and device ids to be used for attachment
  def _process_volume_attachments(
    template: nil,
    autoscaling_group_name: nil,
    execution_role_arn: nil,
    notification_role_arn: nil,
    volume_attachments: nil
  )

    _process_pipeline_autoscaling_action(
      template: template,
      action_name: "VolumeAttachment",
      autoscaling_group_name: autoscaling_group_name,
      execution_role_arn: execution_role_arn,
      notification_role_arn: notification_role_arn,
      notification_metadata: volume_attachments.to_json,
      lambda_code: "#{__dir__}/../aws_autoheal/attach_volume.py"
    )
  end

  # @param volume_attachments [Array] list of key value pairs of volume ids and device ids to be used for attachment
  # @param component_name [String] name of the owning component
  # @param execution_role_name [String] name of the role to be assigned to lambda executor
  # @return [Array] list of security rules required for the lambda executor and notification roles
  def _volume_attachment_security_rules(
    volume_attachments: nil,
    component_name: nil,
    execution_role_name: nil
  )

    # add resource specific rule for each volume for least privilege
    resources = []
    volumes = _parse_volume_attachments(volume_attachments)

    volumes.map do |v|
      resources << "arn:aws:ec2:#{Context.environment.region}:#{Context.environment.account_id}:volume/#{v['VolumeId']}"
    end

    resources << "arn:aws:ec2:#{Context.environment.region}:#{Context.environment.account_id}:instance/*"

    [
      # Allow attachment of volumes
      IamSecurityRule.new(
        roles: "#{component_name}.#{execution_role_name}",
        actions: %w(ec2:AttachVolume),
        resources: resources
      ),
      IamSecurityRule.new(
        roles: "#{component_name}.#{execution_role_name}",
        actions: %w(
          logs:CreateLogStream
          logs:PutLogEvents
        ),
        resources: %w(arn:aws:logs:*:*:*)
      ),
      # Allow instance to grant permission to use CMK Key
      IamSecurityRule.new(
        roles: "#{component_name}.#{execution_role_name}",
        actions: [
          "kms:CreateGrant"
        ],
        resources: Context.kms.secrets_key_arn
      )
    ]
  end

  # Parses Pipeline::Autoheal::VolumeAttachment resource specified in YAML
  # @param resource [Hash] subset of the component YAML definition for Pipeline::Autoheal::VolumeAttachment
  # @return [Array] list of key value pairs for volumes ids and device index values for attachment
  def _parse_volume_attachments(resource)
    attachments = []
    resource.each do |name, definition|
      definition = Context.component.replace_variables(definition)

      volume = JsonTools.get(definition, "Properties.VolumeId").to_s
      device = JsonTools.get(definition, "Properties.Device").to_s

      unless device =~ %r{/dev/[a-z1-9]+} && volume =~ /vol-[a-z0-9]+/
        raise ArgumentError, "#{name} - Invalid value specified for device #{device} or volume #{volume}"
      end

      attachments << { "VolumeId" => volume, "Device" => device }
    end
    attachments
  end
end
