# Module responsible for generating AWS::Lambda::Function template
module LambdaFunctionBuilder
  # @param template [Hash] template carried into the function
  # @param function_definition [Hash] Definition for lambda function
  # @param resource_name [String] Logical name for Lambda function resource
  # @param security_group_ids [Array] List of security groups ids for vpc configuration
  # See CloudFormation AWS::Lambda::Function documentation for valid property values
  # http://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-lambda-function.html
  def _process_lambda_function(
    template: nil,
    function_definition: nil,
    resource_name: nil,
    role: nil,
    security_group_ids: nil
  )

    name, definition = function_definition.first
    name = resource_name unless resource_name.nil?

    # Replace any context variables
    Context.component.replace_variables(definition)

    template["Resources"][name] = {
      "Type" => "AWS::Lambda::Function",
      "Properties" => {
        "Handler" => JsonTools.get(definition, "Properties.Handler"),
        "Role" => role,
        "Runtime" => JsonTools.get(definition, "Properties.Runtime")
      }
    }

    resource = template["Resources"][name]

    code = JsonTools.get(definition, "Properties.Code")
    raise "Unknown value for code, specify valid package filename" unless code.is_a?(String)

    # For local file use ZipFile CF property for function as construct inline
    # Required for pipeline managed Lambda resources
    if File.exist?(code)
      resource["Properties"]["Code"] = {
        'ZipFile' => _process_local_file(code)
      }
    else
      cd_artefact_path = Defaults.cd_artefact_path(component_name: @component_name)

      resource["Properties"]["Code"] = {
        "S3Bucket" => Context.s3.lambda_artefact_bucket_name,
        "S3Key" => "#{cd_artefact_path}/#{code}"
      }
    end
    
    #Cheking if TracingConfig property is defined in the configuration
    tracing_config = JsonTools.get(definition, "Properties.TracingConfig", nil)

    if tracing_config.nil? or tracing_config.empty?
      Log.debug "TracingConfig Proprty is not defined in the configuration"
    else
      resource["Properties"]["TracingConfig"] = { "Mode" => tracing_config}
    end

    #Cheking if Lambda Layers property is defined in the configuration
    layers = JsonTools.get(definition, "Properties.Layers", nil)
    if layers.nil? or layers.empty?
      Log.debug "Layers are not defined in the configuration"
    else
      Log.debug "Layers are defined in the configuration. Setting the Template with the layers."
      resource["Properties"]["Layers"] = layers
    end


    deadLetterQueueValue = JsonTools.get(definition, "Properties.DeadLetterConfig", nil)

    unless deadLetterQueueValue.nil?
      resource["Properties"]["DeadLetterConfig"] = {
        'TargetArn' => deadLetterQueueValue
      }
    end

    JsonTools.transfer(definition, "Properties.MemorySize", resource)
    JsonTools.transfer(definition, "Properties.ReservedConcurrentExecutions", resource)
    JsonTools.transfer(definition, "Properties.Timeout", resource)
    JsonTools.transfer(definition, "Properties.Environment", resource)
    
    size = JsonTools.get(definition, "Properties.EphemeralStorage.Size", nil)
    resource["Properties"]["EphemeralStorage"] = JsonTools.get(definition, "Properties.EphemeralStorage") unless size.nil?
    resource["Properties"]["KmsKeyArn"] = Context.kms.secrets_key_arn

    if security_group_ids.nil? || security_group_ids.empty?
      Log.debug "No security groups defined. Skipping VPC Configuration"
    else
      # Only allow private subnets for Lambda created ENIs
      #security_group_ids << Context.asir.destination_sg_id if ingress? ## Not needed to keep lambda open for connect from a diff app's compoennt
      subnet_ids = Context.environment.subnet_ids("@private")
      resource["Properties"]["VpcConfig"] = {
        "SecurityGroupIds" => security_group_ids,
        "SubnetIds" => subnet_ids
      }
    end

    template["Resources"]["#{name}LogGroup"] = {
      "Type" => "AWS::Logs::LogGroup",
      "Properties" => {
        "LogGroupName" => {
          "Fn::Join" => ["", ["/aws/lambda/", { "Ref" => name }]]
        },
        "RetentionInDays" => 30
      }
    }

    template["Outputs"]["#{name}Name"] = {
      "Description" => "Name of the function",
      "Value" => { "Ref" => name }
    }
    template["Outputs"]["#{name}Arn"] = {
      "Description" => "Arn of the function",
      "Value" => { "Fn::GetAtt" => [name, "Arn"] }
    }
  end

  # Update references template with AWS::Lambda::Version template resources
  # and outputs
  # @param template [Hash] CloudFormation template hash
  # @param lambda_function [String] Lambda function physical resource name
  # @param lambda_function_name [String] Lambda function logical resource name
  def _process_lambda_version(
    template:,
    lambda_function:,
    lambda_function_name:
  )
    template["Resources"]["#{lambda_function_name}Version"] = {
      "Type" => "AWS::Lambda::Version",
      "Properties" => {
        "FunctionName" => lambda_function
      }
    }

    template["Outputs"]["#{lambda_function_name}Version"] = {
      "Description" => "Version Number",
      "Value" => { "Fn::GetAtt" => ["#{lambda_function_name}Version", "Version"] }
    }

    template["Outputs"]["#{lambda_function_name}VersionArn"] = {
      "Description" => "Version ARN",
      "Value" => { "Ref" => "#{lambda_function_name}Version" }
    }
  end

  # Update references template with AWS::Lambda::Alias resources and outputs
  # @param template [Hash] Reference to CloudFormation template hash
  # @param alias_definition [Hash] Lambda alias resource definition
  def _process_lambda_alias(
    template:,
    alias_definition:
  )
    name, definition = alias_definition.first

    template["Resources"][name] = {
      "Type" => "AWS::Lambda::Alias",
      "Properties" => {
        "FunctionName" => JsonTools.get(definition, "Properties.FunctionName"),
        "FunctionVersion" => JsonTools.get(definition, "Properties.FunctionVersion"),
        "Name" => JsonTools.get(definition, "Properties.Name", name.downcase)
      }
    }

    template["Outputs"]["#{name}Arn"] = {
      "Description" => "#{name} Alias Arn",
      "Value" => { "Ref" => name }
    }
  end

  # Update references template with AWS::Lambda::EventSourceMapping resources and outputs
  # @param template [Hash] Reference to CloudFormation template hash
  # @param function_name [String] Name of the target function
  # @param definitions [Hash] Lambda event source mapping definition
  def _process_event_source_mapping(
    template:,
    function_name:,
    definitions:
  )

    definitions.each do |name, definition|
      template["Resources"][name] = {
        "Type" => "AWS::Lambda::EventSourceMapping",
        "Properties" => {
          "BatchSize" => JsonTools.get(definition, "Properties.BatchSize", 10),
          "Enabled" => JsonTools.get(definition, "Properties.Enabled", true),
          "FunctionName" => JsonTools.get(definition, "Properties.FunctionName", function_name),
          "EventSourceArn" => JsonTools.get(definition, "Properties.EventSourceArn"),
        }
      }

      JsonTools.transfer(definition, 'Properties.StartingPosition', template['Resources'][name])
    end
  end

  # Return CloudFormation representation of a local function source file
  # @param filename [String] Location of a local source file
  # @return [Hash] CloudFormation representation of a source file
  def _process_local_file(filename)
    join_array = []
    File.readlines(filename).each { |line| join_array.push(line) }
    { 'Fn::Join' => ['', join_array] }
  end

  # Downloads unpacks and uploads lambda artefact to a staging area for deployment
  # @param component_name [String] Artefact file name specified for the lambda function
  # @param artefacts [List] List of artefacts to be uploaded
  def _upload_package_artefacts(component_name:, artefacts:)
    require 'util/archive'

    download_artefact_bucket = Context.s3.artefact_bucket_name
    upload_artefact_bucket = Context.s3.lambda_artefact_bucket_name

    cd_artefact_path = Defaults.cd_artefact_path(component_name: component_name)
    tmpdir = Dir.mktmpdir
    local_file_name = "#{tmpdir}/app.tar.gz"

    begin
      AwsHelper.s3_download_object(
        bucket: download_artefact_bucket,
        key: "#{cd_artefact_path}/app.tar.gz",
        local_filename: local_file_name
      )
      Util::Archive.untgz!(local_file_name)
    rescue => e
      raise "Unable to download and unpack package " \
        "from #{download_artefact_bucket}/#{cd_artefact_path} - #{e}"
    end

    artefacts.each do |artefact_name|
      local_artefact_file_name = File.join tmpdir, artefact_name

      unless File.exist?(local_artefact_file_name)
        raise "Unable to locate #{artefact_name}. " \
          "Ensure lambda code is packaged as a single zip or jar artefact" \
          " into $PAYLOAD_DIR during the upload stage"
      end

      begin
        file_name = File.basename(local_artefact_file_name)
        Log.debug "Uploading file to #{upload_artefact_bucket}/#{cd_artefact_path}/#{file_name}"
        AwsHelper.s3_upload_file(
          upload_artefact_bucket,
          "#{cd_artefact_path}/#{file_name}",
          local_artefact_file_name
        )
      rescue => e
        raise "Unable to upload file to #{upload_artefact_bucket}/#{cd_artefact_path}/#{file_name} - #{e}"
      end
    end
  rescue => e
    raise "Unable to unpack and upload lambda artefact - #{e}"
  ensure
    FileUtils.rm_rf tmpdir
  end

  # Return array of instance base security rules to be included in security groups
  # @param component_name [String] name of the component to apply rules to
  # @param role_name [String] Name of a role to assign rules to
  # @return [Array] list of security rules
  def _base_security_rules(
    component_name:,
    role_name:
  )
    [
      # Allow VPC configuration
      IamSecurityRule.new(
        roles: "#{component_name}.#{role_name}",
        actions: %w(
          logs:CreateLogStream
          logs:PutLogEvents
        ),
        resources: '*'
      ),

      # Allow Xray monitoring
      IamSecurityRule.new(
        roles: "#{component_name}.ExecutionRole",
        actions: %w(
          xray:PutTraceSegments
          xray:PutTelemetryRecords
        ),
        resources: '*'
      ),

      # Allow Logs
      IamSecurityRule.new(
        roles: "#{component_name}.#{role_name}",
        actions: %w(
          ec2:CreateNetworkInterface
          ec2:DescribeNetworkInterfaces
          ec2:DeleteNetworkInterface
          ec2:DescribeSubnets
          ec2:DescribeVpcs
        ),
        resources: '*'
      ),

      # Allow access to Create network interface
      IamSecurityRule.new(
        roles: "#{component_name}.#{role_name}",
        actions: ['cloudwatch:PutMetricData'],
        resources: '*'
      ),

      # Allow instance to decrypt secrets using KMS
      IamSecurityRule.new(
        roles: "#{component_name}.#{role_name}",
        actions: %w(
          kms:Decrypt
          kms:DescribeKey
          kms:Encrypt
          kms:GenerateDataKey
          kms:GenerateDataKeyWithoutPlaintext
          kms:GenerateRandom
          kms:ReEncrypt*
        ),
        resources: Context.kms.secrets_key_arn
      ),
      # Bucket GetLocation access
      IamSecurityRule.new(
        roles: "#{component_name}.#{role_name}",
        actions: ["s3:GetBucketLocation"],
        resources: %W(
          #{Context.s3.ams_bucket_arn}
          #{Context.s3.qda_bucket_arn}
          #{Context.s3.as_bucket_arn}
          #{Context.s3.legacy_bucket_arn}
          #{Context.s3.artefact_bucket_arn}
        )
      ),

      # Bucket List access
      IamSecurityRule.new(
        roles: "#{@component_name}.#{role_name}",
        actions: %w(
          s3:ListBucket
          s3:ListBucketVersions
          s3:ListBucketMultipartUploads
        ),
        resources: %W(
          #{Context.s3.ams_bucket_arn}
          #{Context.s3.qda_bucket_arn}
          #{Context.s3.as_bucket_arn}
          #{Context.s3.legacy_bucket_arn}
        )
      ),

      # Bucket Read access
      IamSecurityRule.new(
        roles: "#{component_name}.#{role_name}",
        actions: %w(
          s3:GetObject
          s3:GetObjectVersion
        ),
        resources: %W(
          #{Context.s3.ams_bucket_arn}/*
          #{Context.s3.qda_bucket_arn}/*
          #{Context.s3.as_bucket_arn}/*
          #{Context.s3.legacy_bucket_arn}/*
          #{Context.s3.artefact_bucket_arn}/#{Defaults.cd_artefact_path}/*
          #{Context.s3.lambda_artefact_bucket_arn}/#{Defaults.cd_artefact_path}/*
        )
      ),

      # Bucket Version and Lifecycle Management
      IamSecurityRule.new(
        roles: "#{component_name}.#{role_name}",
        actions: %w(
          s3:GetBucketVersioning
          s3:PutBucketVersioning
          s3:GetLifecycleConfiguration
          s3:PutLifecycleConfiguration
        ),
        resources: Context.s3.as_bucket_arn
      ),

      # Bucket Write access
      IamSecurityRule.new(
        roles: "#{component_name}.#{role_name}",
        actions: %w(
          s3:PutObject
          s3:PutObjectAcl
          s3:DeleteObject
          s3:DeleteObjectVersion
          s3:RestoreObject
          s3:ListMultipartUploadParts
          s3:AbortMultipartUpload
        ),
        resources: %W(
          #{Context.s3.qda_bucket_arn}/*
          #{Context.s3.as_bucket_arn}/*
        )
      )
    ]
  end

  def _dead_letter_queue_permission(
    component_name:,
    role_name:,
    definition:
  )
    Context.component.replace_variables(definition)
    [
      IamSecurityRule.new(
        roles: "#{component_name}.#{role_name}",
        actions: ["sqs:SendMessage"],
        resources: JsonTools.get(definition, "Properties.DeadLetterConfig")
      )
    ]
  end

end
