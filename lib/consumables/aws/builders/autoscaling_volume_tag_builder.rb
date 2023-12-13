# Extends PipelineAutoscalingActionBuilder for tag assignment to volumes created with AutoScaled resources

require_relative "pipeline_autoscaling_action_builder"

module AutoscalingVolumeTagBuilder
  include PipelineAutoscalingActionBuilder

  # Generates CloudFormation resources by calling generic _process_pipeline_autoscaling_action
  # @param template [Hash] - CloudFormation template passed into the function
  # @param autoscaling_group_name [String] - Logical name for the AutoscalingGroup resource
  # @param execution_role_arn [String] - Reference to AWS IAM role arn identifier (for Lambda execution)
  # @param notification_role_arn [String] - Reference to AWS IAM role arn identifier (For Autoscaling notifications)
  # @param tags [Hash] - Collection of tag key value pairs to be passed to autoscaling hook
  def _process_volume_tagger(
    template: nil,
    autoscaling_group_name: nil,
    execution_role_arn: nil,
    notification_role_arn: nil,
    tags: nil,
    volume_attachments: []
  )

    if volume_attachments.nil? || volume_attachments.empty?
      notification_metadata = tags.to_json
    else
      tags.push({ key: 'volumeIds', value: volume_attachments })
      notification_metadata = tags.to_json
    end
    _process_pipeline_autoscaling_action(
      template: template,
      action_name: "VolumeTagger",
      autoscaling_group_name: autoscaling_group_name,
      execution_role_arn: execution_role_arn,
      notification_role_arn: notification_role_arn,
      notification_metadata: notification_metadata,
      lambda_code: "#{__dir__}/../common/volume_tagger.py"
    )
  end

  # Generates IAM security rules required for execution of the volume tagging action
  # @param component_name [String] - name of the component to attach volume tagging resources to
  # @param execution_role_name [String] - Reference to AWS IAM role name (for Lambda execution)
  def _volume_tagger_security_rules(
    component_name: nil,
    execution_role_name: nil
  )

    [
      # Allow attachment of volumes
      IamSecurityRule.new(
        roles: "#{component_name}.#{execution_role_name}",
        actions: %w(
          tag:addResourceTags
          tag:getTagKeys
          tag:getTagValues
          ec2:DescribeInstanceAttribute
          ec2:CreateTags
        ),
        resources: '*'
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
