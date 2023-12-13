require "util/json_tools"
require "util/tag_helper"

module TaskDefinitionBuilder
  def _process_task_definition(
    component_name:,
    template:,
    task_definition:,
    tags: nil
  )
    name, definition = task_definition.first

    template["Resources"]["#{name}LogGroup"] = {
      "Type" => "AWS::Logs::LogGroup",
      "Properties" => {
        "LogGroupName" => "/qcp/ecs/task/#{Defaults.component_stack_name(name)}",
        "RetentionInDays" => 7
      }
    }

    template["Resources"][name] = {
      "Type" => "AWS::ECS::TaskDefinition",
      "Properties" => {
        "Cpu" => JsonTools.get(definition, "Properties.Cpu", 256),
        "ExecutionRoleArn" => Context.component.role_arn(component_name, "ExecutionRole"),
        "Memory" => JsonTools.get(definition, "Properties.Memory", 512),
        "NetworkMode" => "awsvpc",
        "RequiresCompatibilities" => [
          'FARGATE'
        ],
        "Tags" => tags.map { |e| { "Key" => e[:key], "Value" => e[:value] } },
        "TaskRoleArn" => Context.component.role_arn(component_name, "TaskRole"),
      }
    }

    resource = template["Resources"][name]
    resource["Properties"]["ContainerDefinitions"] = Context.component.replace_variables(
      JsonTools.get(definition, 'Properties.ContainerDefinitions', [])
    )

    # Because there could be more than one container definition, we need to
    cd = resource["Properties"]["ContainerDefinitions"].first

    # Default to the latest image tag if @latest alias is supplied
    if cd["Image"] == "@latest"
      repository = "#{Defaults.ecr_repository_name(component_name)}"
      ci_build = Context.component.variable('pipeline', 'CI_Build')
      image_tag = "#{Defaults.ecr_latest_image_tag(component_name, ci_build)}"

      cd["Image"] = "#{Defaults.ecr_registry}/#{repository}:#{image_tag}"
      Log.info("Deploying image: #{Defaults.ecr_registry}/#{repository}:#{image_tag}")
    end

    Context.component.set_variables(component_name, "ECSContainerName" => cd["Name"])

    cd["LogConfiguration"] = {
      "LogDriver" => "awslogs",
      "Options" => {
        "awslogs-group" => { "Ref" => "#{name}LogGroup" },
        "awslogs-region" => { "Ref" => "AWS::Region" },
        "awslogs-stream-prefix" => cd["Name"]
      }
    }

  end

  def _execution_base_security_rules(
    component_name:,
    role_name:
  )
    [
      IamSecurityRule.new(
        roles: "#{component_name}.#{role_name}",
        actions: %w(
          ecr:GetAuthorizationToken
          ecr:BatchCheckLayerAvailability
          ecr:GetDownloadUrlForLayer
          ecr:BatchGetImage
          logs:CreateLogStream
          logs:PutLogEvents
        ),
        resources: '*'
      ),
    ]
  end

  def _task_base_security_rules(
    component_name:,
    role_name:
  )
    [
      # Allow access to CloudWatch metrics
      IamSecurityRule.new(
        roles: "#{component_name}.#{role_name}",
        actions: [
          "cloudwatch:PutMetricData",
        ],
        resources: "*"
      ),
      # Allow task to decrypt secrets using KMS
      IamSecurityRule.new(
        roles: "#{component_name}.#{role_name}",
        actions: [
          "kms:Decrypt",
          "kms:Describe*",
          "kms:Encrypt",
          "kms:GenerateDataKey",
          "kms:GenerateDataKeyWithoutPlaintext",
          "kms:GenerateRandom",
          "kms:ReEncrypt*",
        ],
        resources: Context.kms.secrets_key_arn,
      ),
      IamSecurityRule.new(
        roles: "#{component_name}.#{role_name}",
        actions: [
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:ListBucketVersions",
        ],
        resources: [
          Context.s3.ams_bucket_arn,
          Context.s3.qda_bucket_arn,
          Context.s3.as_bucket_arn,
        ]
      ),
      # Bucket Write access
      IamSecurityRule.new(
        roles: "#{component_name}.#{role_name}",
        actions: [
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:DeleteObject",
          "s3:DeleteObjectVersion",
          "s3:RestoreObject",
          "s3:ListMultipartUploadParts",
          "s3:AbortMultipartUpload",
        ],
        resources: [
          Context.s3.qda_bucket_arn,
          Context.s3.as_bucket_arn,
        ]
      ),
      # Bucket Version and Lifecycle Management
      IamSecurityRule.new(
        roles: "#{component_name}.#{role_name}",
        actions: [
          "s3:GetBucketNotification",
          "s3:GetBucketVersioning",
          "s3:GetLifecycleConfiguration",
          "s3:PutBucketNotification",
          "s3:PutBucketVersioning",
          "s3:PutLifecycleConfiguration",
        ],
        resources: [
          Context.s3.as_bucket_arn
        ]
      ),
      # Allow access to ExecuteCommand
      IamSecurityRule.new(
        roles: "#{component_name}.#{role_name}",
        actions: [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel",
        ],
        resources: "*"
      ),    
    ]
  end
end
