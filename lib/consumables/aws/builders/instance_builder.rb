require_relative "util/metadata_builder"
require "util/json_tools"

module InstanceBuilder
  # Processes AWS::EC2::Instance resource
  #
  # @param template [Hash] CloudFormation template passed in as reference
  # @param instance_definition [Hash]  resource parsed from YAML definition
  # @param instance_profile [String] reference to instance profile
  # @param security_group_ids [Array] list of security groups to be applied
  # @param user_data [String] Base64 generated string to be used for instance user data
  # @param image_id [String] reference to AMI ID to be used for the instance
  # @param default_instance_type [String] default instance type for deployed instance
  # @param shutdown_behaviour [String] default shutdown behaviour for the instance [stop or terminate]
  # @param metadata [Hash] metadata to be included in the resource definition
  def _process_instance(
    template: nil,
    instance_definition: nil,
    instance_profile: nil,
    security_group_ids: nil,
    user_data: nil,
    image_id: nil,
    default_instance_type: "t3a.medium",
    shutdown_behaviour: "terminate",
    metadata: {}
  )
    name, definition = instance_definition.first

    metadata[:user_metadata] = JsonTools.get(definition, "Metadata", {})
    metadata = MetadataBuilder.build(**metadata)

    # Determine subnet id and availability zone to place instance into
    subnet_alias = JsonTools.get(definition, "Properties.SubnetId", "@private")
    zone_alias = JsonTools.get(definition, "Properties.AvailabilityZone", nil)
    if zone_alias.nil?
      zone = nil
      subnet_id = Context.environment.subnet_ids(subnet_alias)[0]
    else
      zone = Context.environment.availability_zones(zone_alias)[0]
      subnet_id = Context.environment.subnet_ids(subnet_alias, { availability_zone: zone })[0]
    end

    template["Resources"][name] = {
      "Type" => "AWS::EC2::Instance",
      "CreationPolicy" => {
        "ResourceSignal" => {
          "Count" => "1",
          "Timeout" => JsonTools.get(definition, "CreationPolicy.ResourceSignal.Timeout", "PT45M"),
        }
      },
      "Metadata" => metadata,
      "Properties" => {
        "IamInstanceProfile" => instance_profile,
        "ImageId" => image_id,
        "InstanceInitiatedShutdownBehavior" => JsonTools.get(definition, "Properties.InstanceInitiatedShutdownBehavior", shutdown_behaviour),
        "InstanceType" => JsonTools.get(definition, "Properties.InstanceType", default_instance_type),
        "SecurityGroupIds" => security_group_ids,
        "SubnetId" => subnet_id,
        "UserData" => user_data,
      }
    }
    resource = template["Resources"][name]

    resource["Properties"]["AvailabilityZone"] = zone unless zone.nil?
    instance_tenancy = JsonTools.get(definition, "Properties.Tenancy",nil)
    resource["Properties"]["Tenancy"] = instance_tenancy unless instance_tenancy.nil?

    JsonTools.transfer(definition, "Properties.Tenancy", resource)
    JsonTools.transfer(definition, "Properties.BlockDeviceMappings", resource)
    JsonTools.transfer(definition, "Properties.EbsOptimized", resource)
    JsonTools.transfer(definition, "Properties.KeyName", resource)
    JsonTools.transfer(definition, "Properties.Monitoring", resource)
    JsonTools.transfer(definition, "Properties.SourceDestCheck", resource)
    JsonTools.transfer(definition, "Properties.CpuOptions.CoreCount", resource)
    JsonTools.transfer(definition, "Properties.CpuOptions.ThreadsPerCore", resource)

    template["Outputs"]["#{name}Id"] = {
      "Description" => "Id of the instance",
      "Value" => { "Ref" => name }
    }
    template["Outputs"]["#{name}PrivateDnsName"] = {
      "Description" => "Private DNS name of the instance",
      "Value" => { "Fn::GetAtt" => [name, "PrivateDnsName"] }
    }
    template["Outputs"]["#{name}PrivateIp"] = {
      "Description" => "Private IP of the instance",
      "Value" => { "Fn::GetAtt" => [name, "PrivateIp"] }
    }
    
  end

  # Generated AWS::CloudWatch::Alarm resource in referenced template
  # @param template [Hash] reference to a CloudFormation template under construction
  # @param instance [String] name of AWS::EC2::Instance resource to link the alarm  resource to
  def _add_recovery_alarm(
    template: nil,
    instance: nil
  )
    template["Resources"]["RecoveryAlarm"] = {
      "Type" => "AWS::CloudWatch::Alarm",
      "Properties" => {
        "AlarmDescription" => "Trigger a recovery for instance",
        "Namespace" => "AWS/EC2",
        "MetricName" => "StatusCheckFailed_System",
        "Statistic" => "Minimum",
        "Period" => "60",
        "EvaluationPeriods" => "10",
        "ComparisonOperator" => "GreaterThanThreshold",
        "Threshold" => "0",
        "AlarmActions" => [{ "Fn::Join" => ["", ["arn:aws:automate:", { "Ref" => "AWS::Region" }, ":ec2:recover"]] }],
        "Dimensions" => [{ "Name" => "InstanceId", "Value" => { "Ref" => instance } }]
      }
    }
  end

  # Upload CD artefacts to S3 for retrieval by deployed instances
  # @param component_name [String] name of the instance component
  # @param platform [String] operating system platform
  # @param soe_ami_id [String] reference AMI used by the instance
  # @param files [Hash] key value pairs of file names and locations to be uploaded
  # @param objects [Hash] key value pairs variables to be converted to flat text files and uploaded
  # @param context_skip_keys [Array] list of keys to be omitted from generated context file
  def _upload_cd_artefacts(
    component_name: nil,
    platform: nil,
    soe_ami_id: nil,
    files: {},
    objects: {},
    context_skip_keys: [],
    pipeline_features: {}
  )

    files ||= {}
    objects ||= {}

    # Upload environment variables for use by the instance Puppet scripts
    bamboo_variables = Context.environment.dump_variables

    bamboo_variables["pipeline_name"] = component_name                # For Splunk system/local/inputs.conf
    bamboo_variables["soe_ami"] = soe_ami_id unless soe_ami_id.nil?   # For Splunk system/local/inputs.conf
    objects["bamboo-vars.conf"] = ObjToText.generate_flat_config(
      variables: bamboo_variables.sort.to_h,
      line_prefix: "bamboo_",
      quote_strings: :special
    )

    Log.info "Creating context variables file for use by the instance"
    # The regex pattern skip the encryption of application secrets before dumping the variable.
    context_variables = Context.component.dump_variables(component_name, context_skip_keys, '^app.([0-9a-zA-Z_\/]+)$')

    objects["context"] = ObjToText.generate_flat_config(
      variables: context_variables.sort.to_h,
      quote_strings: true,
      line_prefix: "export "
    )

    Log.info "Creating features.json file for prospero to use the during deploy"
    features_variables_hash = _pipeline_feature_hash_builder(pipeline_features)
    objects["features.json"] = features_variables_hash.to_json

    case platform
    when :amazon_linux, :rhel, :centos
      objects["context"] = ObjToText.generate_flat_config(
        variables: context_variables.sort.to_h,
        quote_strings: true,
        line_prefix: "export "
      )
      Log.info "Creating features.text file for old pipeline prospero to use the during deploy"
      objects["features.txt"] = ObjToText.generate_flat_config(
        variables: features_variables_hash.sort.to_h,
        flat_hash_config: true
      )
      objects["set_qcp_proxy.sh"] = UserData.process_file(
        "#{__dir__}/../common/linux/set_qcp_proxy.sh",
        "AwsProxy" => Context.environment.variable("aws_proxy", ""),
        "NoProxy" => Context.environment.variable("aws_no_proxy", "")
      )
      objects["set_aws_region.sh"] = UserData.process_file(
        "#{__dir__}/../common/linux/set_aws_region.sh",
        "Region" => Context.environment.region
      )
      files["attach_eni.sh"] = "#{__dir__}/../common/linux/attach_eni.sh"
      files["attach_volume.sh"] = "#{__dir__}/../common/linux/attach_volume.sh"
      files["detach_eni.sh"] = "#{__dir__}/../common/linux/detach_eni.sh"
      files["detach_volume.sh"] = "#{__dir__}/../common/linux/detach_volume.sh"
      files["kms_decrypt.sh"] = "#{__dir__}/../common/linux/kms_decrypt.sh"
      files["kms_decrypt_file.sh"] = "#{__dir__}/../common/linux/kms_decrypt_file.sh"
      files["kms_encrypt.sh"] = "#{__dir__}/../common/linux/kms_encrypt.sh"
      files["kms_encrypt_file.sh"] = "#{__dir__}/../common/linux/kms_encrypt_file.sh"
      files["put_metric.sh"] = "#{__dir__}/../common/linux/put_metric.sh"
      files["configure_s3_versioning.sh"] = "#{__dir__}/../common/linux/configure_s3_versioning.sh"
      files["ssm_parameter_cleanup.sh"] = "#{__dir__}/../common/linux/ssm_parameter_cleanup.sh"
      files["lri_bootstrap.sh"] = "#{__dir__}/../common/linux/lri_bootstrap.sh"

    when :windows
      objects["context.ps1"] = ObjToText.generate_flat_config(
        variables: context_variables.sort.to_h,
        quote_strings: true,
        line_prefix: "$",
        line_ending: "\r\n"
      )

      Log.info "Creating features.text file for old pipeline prospero to use the during deploy "
      objects["features.txt"] = ObjToText.generate_flat_config(
        variables: features_variables_hash.sort.to_h,
        line_ending: "\r\n",
        flat_hash_config: true
      )

      files["BundleConfig.xml"] = "#{__dir__}/../common/windows/BundleConfig.xml"
      files["config.xml"] = "#{__dir__}/../common/windows/config.xml"
      files["helperscripts.psm1"] = "#{__dir__}/../common/windows/helperscripts.psm1"
      files["profile.ps1"] = "#{__dir__}/../common/windows/profile.ps1"
      files["sysprep2008.xml"] = "#{__dir__}/../common/windows/sysprep2008.xml"
      files["windeploy.ps1"] = "#{__dir__}/../common/windows/windeploy.ps1"
      files["SysprepInstance2016.ps1"] = "#{__dir__}/../common/windows/SysprepInstance2016.ps1"
      files["Pipeline.Prospero.ps1"] = "#{__dir__}/../common/windows/Pipeline.Prospero.ps1"
      files["splunkInputs.txt"] = "#{__dir__}/../common/windows/splunkInputs.txt"
      files["splunkappInputs.txt"] = "#{__dir__}/../common/windows/splunkappInputs.txt"
      files["deploymentclient.txt"] = "#{__dir__}/../common/windows/deploymentclient.txt"
      files["server.txt"] = "#{__dir__}/../common/windows/server.txt"
      files["trend_agent_reg.ps1"] = "#{__dir__}/../common/windows/trend_agent_reg.ps1"
      files["trend_sched_task.xml"] = "#{__dir__}/../common/windows/trend_sched_task.xml"
      files["lri_bootstrap.ps1"] = "#{__dir__}/../common/windows/lri_bootstrap.ps1"
    end

    artefact_bucket = Context.s3.artefact_bucket_name
    cd_artefact_path = Defaults.cd_artefact_path(component_name: component_name)

    # Upload the files
    files.each do |name, path|
      AwsHelper.s3_upload_file(artefact_bucket, "#{cd_artefact_path}/#{name}", path)
    end

    # Upload the objects
    objects.each do |name, contents|
      AwsHelper.s3_put_object(artefact_bucket, "#{cd_artefact_path}/#{name}", contents)
    end
  end

  # Return array of platform base security rules to be included in security groups
  # @param destination [String] security group to add rules to

  # @return [Array] list of security rules
  def _platform_security_rules(destination: nil)
    [
      # Allow default "platform" access (basically SSH)
      IpSecurityRule.new(
        sources: Defaults.default_inbound_sources,
        destination: destination,
        ports: Defaults.default_inbound_ports,
        allow_direct_sg: true,
      ),
      # QCPP-1103 Allow Qualys full port access
      IpSecurityRule.new(
        sources: Defaults.default_qualys_sources,
        destination: destination,
        ports: "ALL:0-65535",
        allow_direct_sg: true,
      )
    ]
  end

  # Return array of instance base security rules to be included in security groups
  # @param component_name [String] name of the component to apply rules to
  # @return [Array] list of security rules
  def _instance_base_security_rules(component_name: nil)
    [
      # Allow access to ssm parameter
      IamSecurityRule.new(
        roles: "#{component_name}.InstanceRole",
        actions: [
          'ssm:DeleteParameter',
          'ssm:DeleteParameters',
          'ssm:DescribeParameters',
          'ssm:GetParameter',
          'ssm:GetParameters',
          'ssm:GetParametersByPath'
        ],
        resources: [
          _ssm_platform_secret_parameter_arn(component_name: component_name)
        ]
      ),
      # Required for Break GLass
      IamSecurityRule.new(
        roles: "#{component_name}.InstanceRole",
        actions: ["ssm:PutParameter"],
        resources: _ssm_parameter_arn(component_name)
      ),

      # Allow instance to decrypt secrets using KMS
      IamSecurityRule.new(
        roles: "#{component_name}.InstanceRole",
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
      # Bucket GetLocation access
      IamSecurityRule.new(
        roles: "#{component_name}.InstanceRole",
        actions: [
          "s3:GetBucketLocation",
        ],
        resources: [
          "#{Context.s3.ams_bucket_arn}",
          "#{Context.s3.qda_bucket_arn}",
          "#{Context.s3.as_bucket_arn}",
          "#{Context.s3.legacy_bucket_arn}",
          "#{Context.s3.artefact_bucket_arn}",
        ]
      ),
      # Bucket List access
      IamSecurityRule.new(
        roles: "#{@component_name}.InstanceRole",
        actions: [
          "s3:ListBucket",
          "s3:ListBucketVersions",
          "s3:ListBucketMultipartUploads",
        ],
        resources: [
          "#{Context.s3.ams_bucket_arn}",
          "#{Context.s3.qda_bucket_arn}",
          "#{Context.s3.as_bucket_arn}",
          "#{Context.s3.legacy_bucket_arn}",
        ]
      ),
      # Bucket Read access
      IamSecurityRule.new(
        roles: "#{component_name}.InstanceRole",
        actions: [
          "s3:GetObject",
          "s3:GetObjectVersion",
        ],
        resources: [
          "#{Context.s3.ams_bucket_arn}/*",
          "#{Context.s3.qda_bucket_arn}/*",
          "#{Context.s3.as_bucket_arn}/*",
          "#{Context.s3.legacy_bucket_arn}/*",
          "#{Context.s3.artefact_bucket_arn}/#{Defaults.cd_artefact_path}/*",
          "#{Context.s3.artefact_bucket_arn}/#{Defaults.cd_common_artefact_path}/*",
        ]
      ),
      # Bucket Write access
      IamSecurityRule.new(
        roles: "#{component_name}.InstanceRole",
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
          "#{Context.s3.qda_bucket_arn}/*",
          "#{Context.s3.as_bucket_arn}/*",
        ]
      ),

      # Bucket Version and Lifecycle Management
      IamSecurityRule.new(
        roles: "#{component_name}.InstanceRole",
        actions: [
          "s3:GetBucketVersioning",
          "s3:PutBucketVersioning",
          "s3:GetLifecycleConfiguration",
          "s3:PutLifecycleConfiguration",
        ],
        resources: [
          Context.s3.as_bucket_arn
        ]
      ),

      # Bucket List access
      IamSecurityRule.new(
        roles: "#{@component_name}.InstanceRole",
        actions: [
          "s3:GetBucketNotification",
          "s3:PutBucketNotification"
        ],
        resources: [
          "#{Context.s3.as_bucket_arn}"
        ]
      ),
    ]
  end

  # This function gets the output of 'qcp-qualys-bootstrap' and if the output has kms arn then add the rule else return empty value
  # @param component_name [String] name of target component for returned security rules
  # @return [Array] list of security rules
  def _instance_qualys_key_rules(component_name: nil)
    qualys_kms_stack_name = Defaults.qualys_kms_stack_name

    Log.debug "Getting Qualys stack output, stack name: #{qualys_kms_stack_name}"
    qualys_stack_resource = AwsHelper.cfn_get_stack_outputs(qualys_kms_stack_name)

    qualys_keyrule = []
    qualys_key_arn = qualys_stack_resource["QualysKeyARN"]

    if !qualys_key_arn.nil?
      Log.debug "Adding permission for Qualys KMS Key: #{qualys_key_arn}"

      qualys_keyrule += [
        IamSecurityRule.new(
          roles: "#{component_name}.InstanceRole",
          actions: [
            "kms:Encrypt"
          ],
          resources: qualys_key_arn
        )
      ]
    else
      Log.warn "Could not find Qualys KMS key, stack name was: #{qualys_kms_stack_name}"
    end

    return qualys_keyrule
  end

  # Return array of legacy security rules used for attachment of volumes and interfaces
  # This functionality has been superseded by aws/autoheal component
  # These rules are made available for backward compatibility
  # @param component_name [String] name of target component for returned security rules
  # @return [Array] list of security rules
  def _instance_legacy_security_rules(component_name: nil)
    [
      # Allow instance to perform some limited operations on itself
      IamSecurityRule.new(
        roles: "#{component_name}.InstanceRole",
        actions: [
          "ec2:AttachVolume",
          "ec2:DetachVolume",
          "ec2:StopInstances",
          "ec2:StartInstances",
        ],
        resources: [
          "arn:aws:ec2:#{Context.environment.region}:#{Context.environment.account_id}:instance/*",
        ],
        condition: {
          "StringLike" => {
            "ec2:ResourceTag/Name" => Defaults.component_name_tag(
              component_name: component_name,
              build: "*"
            ),
          }
        }
      ),
      # Allow instance to grant permission to use CMK Key
      IamSecurityRule.new(
        roles: "#{component_name}.InstanceRole",
        actions: [
          "kms:CreateGrant"
        ],
        resources: Context.kms.secrets_key_arn
      )
    ]
  end

  # Return array of LRI security rules used for SSM Patch manager and associated
  # long running tasks.
  # @return [Array] list of security rules
  def _lri_instance_security_rules(component_name: nil)
    [
      # Allow instance to perform some limited SSM Patching operations on itself
      IamSecurityRule.new(
        roles: "#{component_name}.InstanceRole",
        actions: [
          "ssm:SendCommand",
        ],
        resources: [
          "arn:aws:ssm:*:*:document/AWS-RunPatchBaseline",
        ],
      ),
      IamSecurityRule.new(
        roles: "#{component_name}.InstanceRole",
        actions: [
          "ssm:SendCommand",
        ],
        resources: [
          "arn:aws:ec2:#{Context.environment.region}:#{Context.environment.account_id}:instance/*",
        ],
        condition: {
          "StringLike" => {
            "ssm:ResourceTag/Name" => Defaults.component_name_tag(
              component_name: component_name,
              build: "*"
            ),
          }
        }
      ),

      # Allow instance Describe and List AWS SSM Patch manager resources
      IamSecurityRule.new(
        roles: "#{component_name}.InstanceRole",
        actions: [
          "ssm:GetDeployablePatchSnapshotForInstance",
          "ssm:PutInventory",
          "ssm:PutComplianceItems",
          "ec2messages:AcknowledgeMessage",
          "ec2messages:DeleteMessage",
          "ec2messages:FailMessage",
          "ec2messages:GetEndpoint",
          "ec2messages:GetMessages",
          "ec2messages:SendReply",
          "ssm:DescribeInstancePatchStates",
          "ssm:DescribePatchBaselines",
          "ssm:GetPatchBaseline",
          "ssm:ListCommandInvocations",
          "ssm:ListCommands",
          "ssm:ListComplianceItems",
          "ssm:UpdateInstanceInformation",
          "ssm:DescribeInstanceProperties",
          "ssm:DescribeDocumentParameters"
        ],
        resources: [
          "*",
        ]
      )
    ]
  end

  # Return array of security rules required by deployed instances on first boot
  # These rules allow temporary access to CD artifact buckets /logs prefix for instance deployment logs
  # @param component_name [String] name of target component for returned security rules
  # @return [Array] list of security rules
  def _instance_deploytime_security_rules(component_name: nil)
    return [
      # Log write access
      IamSecurityRule.new(
        roles: "#{component_name}.InstanceRole",
        actions: [
          "s3:PutObject",
          "s3:PutObjectAcl",
        ],
        resources: [
          "#{Context.s3.artefact_bucket_arn}/#{Defaults.log_upload_path(component_name: component_name, type: "deploy")}/*"
        ]
      ),
    ]
  end

  # Return array of security rules required by baked instances
  # These rules allow temporary access to CD artifact buckets /logs prefix for instance bake logs
  # @param component_name [String] name of target component for returned security rules
  # @return [Array] list of security rules
  def _instance_baketime_security_rules(component_name: nil)
    return [
      # Log write access
      IamSecurityRule.new(
        roles: "#{@component_name}.InstanceRole",
        actions: [
          "s3:PutObject",
          "s3:PutObjectAcl"
        ],
        resources: [
          "#{Context.s3.artefact_bucket_arn}/#{Defaults.log_upload_path(component_name: component_name, type: "bake")}/*"
        ]
      ),
    ]
  end

  # Returns platform specific Hash to be used in instance Cloud-init metadata block
  # Pre_prepare section is executed first, deploying artifacts and helper scripts to an instance
  # @param platform [String] Operating system platform
  # @param bucket_name [String] pipeline artefact bucket name
  # @param artefact_path [String] pipeline artefact pipeline artefact path
  # @return [Hash] Hash representng Pre_Prepare section of Cloud-init metadata block
  def _metadata_pre_prepare(platform, bucket_name, artefact_path)
    case platform
    when :amazon_linux, :rhel, :centos
      {
        :pre_prepare => {
          "sources" => {
            "/root/payload" => "https://s3-ap-southeast-2.amazonaws.com/#{bucket_name}/#{artefact_path}/app.tar.gz",
          },
          "files" => {
            "/root/bamboo-vars.conf" => {
              "source" => "https://s3-ap-southeast-2.amazonaws.com/#{bucket_name}/#{artefact_path}/bamboo-vars.conf",
              "owner" => "root",
              "group" => "root",
              "mode" => "000400",
            },
            "/root/features.json" => {
              "source" => "https://s3-ap-southeast-2.amazonaws.com/#{bucket_name}/#{artefact_path}/features.json",
              "owner" => "root",
              "group" => "root",
              "mode" => "000400",
            },
            "/root/features.txt" => {
              "source" => "https://s3-ap-southeast-2.amazonaws.com/#{bucket_name}/#{artefact_path}/features.txt",
              "owner" => "root",
              "group" => "root",
              "mode" => "000400",
            },
            "/etc/profile.d/context.sh" => {
              "source" => "https://s3-ap-southeast-2.amazonaws.com/#{bucket_name}/#{artefact_path}/context",
              "owner" => "root",
              "group" => "root",
              "mode" => "000500",
            },
            "/usr/local/sbin/kms_encrypt" => {
              "source" => "https://s3-ap-southeast-2.amazonaws.com/#{bucket_name}/#{artefact_path}/kms_encrypt.sh",
              "owner" => "root",
              "group" => "root",
              "mode" => "000500",
            },
            "/usr/local/sbin/kms_encrypt_file" => {
              "source" => "https://s3-ap-southeast-2.amazonaws.com/#{bucket_name}/#{artefact_path}/kms_encrypt_file.sh",
              "owner" => "root",
              "group" => "root",
              "mode" => "000500",
            },
            "/usr/local/sbin/kms_decrypt" => {
              "source" => "https://s3-ap-southeast-2.amazonaws.com/#{bucket_name}/#{artefact_path}/kms_decrypt.sh",
              "owner" => "root",
              "group" => "root",
              "mode" => "000500",
            },
            "/usr/local/sbin/kms_decrypt_file" => {
              "source" => "https://s3-ap-southeast-2.amazonaws.com/#{bucket_name}/#{artefact_path}/kms_decrypt_file.sh",
              "owner" => "root",
              "group" => "root",
              "mode" => "000500",
            },
            "/usr/local/sbin/attach_volume" => {
              "source" => "https://s3-ap-southeast-2.amazonaws.com/#{bucket_name}/#{artefact_path}/attach_volume.sh",
              "owner" => "root",
              "group" => "root",
              "mode" => "000500",
            },
            "/usr/local/sbin/attach_eni" => {
              "source" => "https://s3-ap-southeast-2.amazonaws.com/#{bucket_name}/#{artefact_path}/attach_eni.sh",
              "owner" => "root",
              "group" => "root",
              "mode" => "000500",
            },
            "/usr/local/sbin/detach_volume" => {
              "source" => "https://s3-ap-southeast-2.amazonaws.com/#{bucket_name}/#{artefact_path}/detach_volume.sh",
              "owner" => "root",
              "group" => "root",
              "mode" => "000500",
            },
            "/usr/local/sbin/detach_eni" => {
              "source" => "https://s3-ap-southeast-2.amazonaws.com/#{bucket_name}/#{artefact_path}/detach_eni.sh",
              "owner" => "root",
              "group" => "root",
              "mode" => "000500",
            },
            "/etc/profile.d/set_qcp_proxy.sh" => {
              "source" => "https://s3-ap-southeast-2.amazonaws.com/#{bucket_name}/#{artefact_path}/set_qcp_proxy.sh",
              "owner" => "root",
              "group" => "root",
              "mode" => "000555",
            },
            "/etc/profile.d/set_aws_region.sh" => {
              "source" => "https://s3-ap-southeast-2.amazonaws.com/#{bucket_name}/#{artefact_path}/set_aws_region.sh",
              "owner" => "root",
              "group" => "root",
              "mode" => "000555",
            },
            "/usr/local/sbin/put_metric" => {
              "source" => "https://s3-ap-southeast-2.amazonaws.com/#{bucket_name}/#{artefact_path}/put_metric.sh",
              "owner" => "root",
              "group" => "root",
              "mode" => "000500",
            },
            "/usr/local/sbin/configure_s3_versioning" => {
              "source" => "https://s3-ap-southeast-2.amazonaws.com/#{bucket_name}/#{artefact_path}/configure_s3_versioning.sh",
              "owner" => "root",
              "group" => "root",
              "mode" => "000500",
            },
            "/usr/local/sbin/ssm_parameter_cleanup" => {
              "source" => "https://s3-ap-southeast-2.amazonaws.com/#{bucket_name}/#{artefact_path}/ssm_parameter_cleanup.sh",
              "owner" => "root",
              "group" => "root",
              "mode" => "000500",
            },
            "/usr/local/sbin/lri_bootstrap.sh" => {
              "source" => "https://s3-ap-southeast-2.amazonaws.com/#{bucket_name}/#{artefact_path}/lri_bootstrap.sh",
              "owner" => "root",
              "group" => "root",
              "mode" => "000500",
            },
          }
        }
      }
    when :windows
      {
        :pre_prepare => {
          "sources" => {
            "C:\\Windows\\temp\\payload" => "https://s3-ap-southeast-2.amazonaws.com/#{bucket_name}/#{artefact_path}/app.tar.gz",
          },
          "files" => {
            "C:\\Windows\\Temp\\bamboo-vars.conf" => {
              "source" => "https://s3-ap-southeast-2.amazonaws.com/#{bucket_name}/#{artefact_path}/bamboo-vars.conf",
            },
            "C:\\Windows\\Temp\\features.json" => {
              "source" => "https://s3-ap-southeast-2.amazonaws.com/#{bucket_name}/#{artefact_path}/features.json",
            },
            "C:\\Windows\\Temp\\features.txt" => {
              "source" => "https://s3-ap-southeast-2.amazonaws.com/#{bucket_name}/#{artefact_path}/features.txt",
            },
            "C:\\Windows\\Temp\\SysprepInstance2016.ps1" => {
              "source" => "https://s3-ap-southeast-2.amazonaws.com/#{bucket_name}/#{artefact_path}/SysprepInstance2016.ps1",
            },
            "C:\\Windows\\Temp\\windeploy.ps1" => {
              "source" => "https://s3-ap-southeast-2.amazonaws.com/#{bucket_name}/#{artefact_path}/windeploy.ps1",
            },
            "C:\\Windows\\Temp\\BundleConfig.xml" => {
              "source" => "https://s3-ap-southeast-2.amazonaws.com/#{bucket_name}/#{artefact_path}/BundleConfig.xml",
            },
            "C:\\Windows\\Temp\\sysprep2008.xml" => {
              "source" => "https://s3-ap-southeast-2.amazonaws.com/#{bucket_name}/#{artefact_path}/sysprep2008.xml",
            },
            "C:\\Windows\\Temp\\config.xml" => {
              "source" => "https://s3-ap-southeast-2.amazonaws.com/#{bucket_name}/#{artefact_path}/config.xml",
            },
            "C:\\Windows\\context.ps1" => {
              "source" => "https://s3-ap-southeast-2.amazonaws.com/#{bucket_name}/#{artefact_path}/context.ps1",
            },
            "C:\\Program Files\\WindowsPowerShell\\Modules\\HelperScripts\\HelperScripts.psm1" => {
              "source" => "https://s3-ap-southeast-2.amazonaws.com/#{bucket_name}/#{artefact_path}/helperscripts.psm1",
            },
            "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\Profile.ps1" => {
              "source" => "https://s3-ap-southeast-2.amazonaws.com/#{bucket_name}/#{artefact_path}/profile.ps1",
            },
            "C:\\Windows\\Temp\\Pipeline.Prospero.ps1" => {
              "source" => "https://s3-ap-southeast-2.amazonaws.com/#{bucket_name}/#{artefact_path}/Pipeline.Prospero.ps1",
            },
            "C:\\Windows\\Temp\\splunkInputs.txt" => {
              "source" => "https://s3-ap-southeast-2.amazonaws.com/#{bucket_name}/#{artefact_path}/splunkInputs.txt",
            },
            "C:\\Windows\\Temp\\splunkappInputs.txt" => {
              "source" => "https://s3-ap-southeast-2.amazonaws.com/#{bucket_name}/#{artefact_path}/splunkappInputs.txt",
            },
            "C:\\Windows\\Temp\\deploymentclient.txt" => {
              "source" => "https://s3-ap-southeast-2.amazonaws.com/#{bucket_name}/#{artefact_path}/deploymentclient.txt",
            },
            "C:\\Windows\\Temp\\server.txt" => {
              "source" => "https://s3-ap-southeast-2.amazonaws.com/#{bucket_name}/#{artefact_path}/server.txt",
            },
            "C:\\Windows\\Temp\\trend_agent_reg.ps1" => {
              "source" => "https://s3-ap-southeast-2.amazonaws.com/#{bucket_name}/#{artefact_path}/trend_agent_reg.ps1",
            },
            "C:\\Windows\\Temp\\trend_sched_task.xml" => {
              "source" => "https://s3-ap-southeast-2.amazonaws.com/#{bucket_name}/#{artefact_path}/trend_sched_task.xml",
            },
            "C:\\Windows\\Temp\\lri_bootstrap.ps1" => {
              "source" => "https://s3-ap-southeast-2.amazonaws.com/#{bucket_name}/#{artefact_path}/lri_bootstrap.ps1",
            }
          }
        }
      }
    end
  end

  # Returns platform specific Hash to be used in instance Cloud-init metadata block
  # Pre-deploy section is responsible for SOE policy enforcement
  # @param platform [String] Operating system platform
  # @return [Hash] returns pre deployment metadata. used for configuration management enforcement
  def _metadata_pre_deploy(platform)
    case platform
    when :amazon_linux, :rhel, :centos
      {
        :pre_deploy => {
          "commands" => {
            "01-prospero-deploy" => {
              "command" => "prospero -vr deploy 2>&1 | tee -a /var/log/prospero_deploy.$(date '+%d_%m_%Y').log",
              "cwd" => "/usr/local/sbin"
            },
            "02-prospero-enforce" => {
              "command" => "prospero -v 2>&1 | tee -a /var/log/prospero_enforce.$(date '+%d_%m_%Y').log",
              "cwd" => "/usr/local/sbin"
            }
          }
        }
      }
    else
      {}
    end
  end

  # Returns platform specific Hash to be used in instance Cloud-init metadata block for Long Running Instances (LRI)
  # Post-deploy section is responsible for registration against a Puppet Master and post deployment clean up
  # @param platform [Symbol] Operating system platform
  # @param puppet_server The Puppet Server to register the instance with
  # @param puppet_environment The Puppet Environment to associate the instance with
  # @param puppet_development The Puppet Development flag value
  # @return [Hash] post deployment metadata used for cleanup
  def _metadata_post_deploy_lri(platform, puppet_server, puppet_environment, puppet_development)
    case platform
    when :amazon_linux, :rhel, :centos

      metadata = {
        :post_deploy => {
          "commands" => {
            "01-lri_bootstrap" => {
              "command" => "lri_bootstrap.sh -s #{puppet_server} -e #{puppet_environment} -d #{puppet_development} | tee -a /var/log/lri_bootstrap.log; test ${PIPESTATUS[0]} -eq 0",
              "cwd" => "/usr/local/sbin",
            },
            "02-cleanup" => {
              "command" => "rm -rf /root/payload"
            },
            "03-list-installed-packages" => {
              "command" => "rpm -qa | sort"
            },
            "04-yum-repolist" => {
              "command" => "yum repolist"
            }
          }
        }
      }

      #unless Defaults.ad_join_domain.blank?
      #  metadata[:post_deploy]["commands"]["05-adflush"] = {
      #    "command" => "adflush -f && service centrifydc restart"
      #  }
      #end
    when :windows

      metadata = {
        :post_deploy => {
          "commands" => {
            "01-lri_bootstrap" => {
              "command" => "powershell.exe -File C:\\Windows\\Temp\\lri_bootstrap.ps1 -PuppetMaster #{puppet_server} -PuppetEnvironment #{puppet_environment} -PuppetDevelopment #{puppet_development} 2>&1 > C:\\Windows\\Temp\\lri_bootstrap.log",
              "waitAfterCompletion" => "0",
            },
            # Delete the payload directory
            "02-cleanup" => {
              "command" => "if exist C:\\Windows\\Temp\\payload rmdir C:\\Windows\\Temp\\payload /s /q",
              "waitAfterCompletion" => "0",
            }
          }
        }
      }
    end
    return metadata
  end

  # Returns platform specific Hash to be used in instance Cloud-init metadata block
  # Post-deploy section is responsible for post deployment clean up
  # @param platform [Symbol] Operating system platform
  # @return [Hash] post deployment metadata used for cleanup
  def _metadata_post_deploy(platform)
    case platform
    when :amazon_linux, :rhel, :centos

      metadata = {
        :post_deploy => {
          "commands" => {
            "01-cleanup" => {
              "command" => "rm -rf /root/payload"
            },
            "02-list-installed-packages" => {
              "command" => "rpm -qa | sort"
            },
            "03-yum-repolist" => {
              "command" => "yum repolist"
            }
          }
        }
      }

      #unless Defaults.ad_join_domain.blank?
      #  metadata[:post_deploy]["commands"]["04-adflush"] = {
      #    "command" => "adflush -f && service centrifydc restart"
      #  }
      #end
    when :windows

      metadata = {
        :post_deploy => {
          "commands" => {
            # Delete the payload directory
            "01-cleanup" => {
              "command" => "if exist C:\\Windows\\Temp\\payload rmdir C:\\Windows\\Temp\\payload /s /q",
              "waitAfterCompletion" => "0",
            }
          }
        }
      }
    end
    return metadata
  end

  # Returns platform specific Hash to be used in instance Cloud-init metadata block
  # Post-deploy section is responsible for post deployment clean up
  # @param platform [Symbol] Operating system platform
  # @return [Hash] post deployment metadata used for cleanup
  def _metadata_bake_post_deploy(platform)
    case platform
    when :amazon_linux, :rhel, :centos
      {
        :post_deploy => {
          "commands" => {
            "01-cleanup" => {
              "command" => "rm -rf /root/payload"
            },
            "02-list-installed-packages" => {
              "command" => "rpm -qa | sort"
            },
            "03-yum-repolist" => {
              "command" => "yum repolist"
            }
          }
        }
      }
    when :windows
      {
        :post_deploy => {
          "commands" => {
            # Delete the payload directory
            "01-cleanup" => {
              "command" => "if exist C:\\Windows\\Temp\\payload rmdir C:\\Windows\\Temp\\payload /s /q",
              "waitAfterCompletion" => "0"
            }
          }
        }
      }
    end
  end

  # @param component_name [String] name of the deployed component
  # @param bucket_name [String] name of the S3 artefact bucket
  # @return [Hash] authentication metadata for S3 access
  def _metadata_auth(component_name, bucket_name)
    {
      :auth => {
        "BakeS3AccessAuth" => {
          "type" => "s3",
          "roleName" => Context.component.role_name(component_name, "InstanceRole"),
          "buckets" => [bucket_name]
        }
      }
    }
  end

  def _ssm_parameter_arn(component_name)
    sections = Defaults.sections
    breakglass_ssm_arn = [
      "arn:aws:ssm",
      Context.environment.region,
      Context.environment.account_id,
      "parameter/#{sections[:ams]}-#{sections[:qda]}-#{sections[:as]}-#{sections[:ase]}-#{sections[:branch]}-#{sections[:build]}-#{component_name}-pwd-*"
    ].join(':')

    qualys_ssm_arn = [
      "arn:aws:ssm",
      Context.environment.region,
      Context.environment.account_id,
      "parameter/#{sections[:ams]}-#{sections[:qda]}-#{sections[:as]}-#{sections[:ase]}-#{sections[:branch]}-#{sections[:build]}-#{component_name}-Qualys-*"
    ].join(':')

    [
      breakglass_ssm_arn,
      qualys_ssm_arn
    ]
  end

  # pipeline features hash builder
  # @return [Hash] key value pair. e.g {"features" => {"datadog" => {"status" => "enabled"}}}
  def _pipeline_feature_hash_builder(pipeline_features)
    return {} if pipeline_features.empty?

    feature_properties_hash = { "features" => {} }
    pipeline_features.map { |f| feature_properties_hash['features'][f.name] = f.feature_properties }

    return feature_properties_hash
  end

  # Constructs AD OU path based on the giving value, ams, qda, as and env
  # if "@default" value is passed, then result looks as following: "OU=#{as},OU=#{qda},OU=#{ams},OU=#{env},DC=qcpaws,DC=qantas,DC=com,DC=au"
  # overwise, current_value is returned
  # @param [String] current_value
  # @param [String] ams
  # @param [String] qda
  # @param [String] as
  # @param [String] env
  # @return [String] ActiveDirectory path
  def _resolve_default_ou_path(current_value:, ams:, qda:, as:, env:)
    result = current_value

    # always fallback to pre-calculated OU structure value
    if current_value.nil? || current_value == "@default"
      result = _default_ou_path(
        ams: ams,
        qda: qda,
        as: as,
        env: env
      )
    end

    result
  end

  # Constructs AD OU path based on the giving ams, qda, as and env
  # Result looks as following: "OU=#{as},OU=#{qda},OU=#{ams},OU=#{env},DC=qcpaws,DC=qantas,DC=com,DC=au"
  # @param [String] ams
  # @param [String] qda
  # @param [String] as
  # @param [String] env
  # @return [String] ActiveDirectory path
  def _default_ou_path(ams:, qda:, as:, env:)
    [ams, qda, as, env].each do |value|
      raise ArgumentError if value.nil? || value.empty?
    end

    # OU=01,OU=C019,OU=AMS01,OU=Prod,DC=qcpaws,DC=qantas,DC=com,DC=au
    # Prod/AMS01/C019/01
    env_value = env.downcase == 'prod' ? 'Prod' : 'NonProd'

    "OU=#{as},OU=#{qda},OU=#{ams},OU=#{env_value},DC=qcpaws,DC=qantas,DC=com,DC=au"
  end

  def _ssm_platform_secret_parameter_arn(component_name: nil)
    sections = Defaults.sections
    build_number = sections[:build]

    unless component_name.nil?
      persist_component_build_number = Context.component.build_number(component_name)
      if !persist_component_build_number.nil?
        Log.debug "This component #{component_name} is persisted from build number #{persist_component_build_number}. Updating the current build number #{build_number} with the persisted build number #{persist_component_build_number}"
        build_number = persist_component_build_number
      else
        Log.debug "Component #{component_name}  is not having any previous persist build reference. So, proceeding with the current build number #{build_number}"
      end
    end

    [
      "arn:aws:ssm",
      Context.environment.region,
      Context.environment.account_id,
      "parameter/platform/#{sections[:ams]}/#{sections[:qda]}/#{sections[:as]}/#{sections[:ase]}/#{sections[:branch]}/#{build_number}/*"
    ].join(':')
  end

  def _ssm_platform_secret_path
    sections = Defaults.sections
    path = [
      "/platform",
      sections[:ams],
      sections[:qda],
      sections[:as],
      sections[:ase],
      sections[:branch],
      sections[:build],
    ].join('/')
    return path
  end
end
