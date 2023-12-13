require "util/json_tools"
require "uri"

module EmrClusterBuilder
  # Generates a CloudFormation AWS::EMR::Cluster resource
  # @param template [Hash] template definition to generate resource into
  # @param cluster_definition [Hash] cluster definition configuration properties
  # @param component_name [Hash] cluster definition configuration properties
  # @param job_role [String] Cluster Service IAM role
  # @param master_security_group_id [String] Security Group to be assigned to the master node
  # @param slave_security_group_id [String] Security Group to be assigned to the slave nodes
  # @param service_security_group_id [String] Security Group to be assigned to the service
  # @param additional_master_security_group_ids [Array] Additional security Groups to be assigned to the master node
  # @param additional_slave_security_group_ids [Array] Additional Security Groups to be assigned to the slave nodes
  def _process_emr_cluster(
    template: nil,
    cluster_definition: nil,
    component_name: nil,
    job_role: nil,
    master_security_group_id: nil,
    slave_security_group_id: nil,
    service_security_group_id: nil,
    additional_master_security_group_ids: [],
    additional_slave_security_group_ids: []
  )
    name, definition = cluster_definition.first

    Context.component.replace_variables(definition)

    template["Resources"][name] = {
      "Type" => "AWS::EMR::Cluster",
      "Properties" => {
        "Applications" => JsonTools.get(definition, "Properties.Applications"),
        "AutoScalingRole" => "EMR_AutoScaling_DefaultRole",
        "Instances" => JsonTools.get(definition, "Properties.Instances"),
        "JobFlowRole" => job_role,
        "LogUri" => _log_uri(component_name),
        "Name" => _fq_name(component_name, name),
        "ReleaseLabel" => JsonTools.get(definition, "Properties.ReleaseLabel"),
        "ServiceRole" => "EMR_DefaultRole",
        "VisibleToAllUsers" => true,
      }
    }
    resource = template["Resources"][name]

    JsonTools.transfer(definition, "Properties.AdditionalInfo", resource)

    # Configure EMR cluster instances
    resource["Properties"]["Instances"]["AdditionalMasterSecurityGroups"] = additional_master_security_group_ids unless additional_master_security_group_ids.nil?
    resource["Properties"]["Instances"]["AdditionalSlaveSecurityGroups"] = additional_slave_security_group_ids unless additional_slave_security_group_ids.nil?
    resource["Properties"]["Instances"]["EmrManagedMasterSecurityGroup"] = master_security_group_id
    resource["Properties"]["Instances"]["EmrManagedSlaveSecurityGroup"] = slave_security_group_id
    resource["Properties"]["Instances"]["ServiceAccessSecurityGroup"] = service_security_group_id
    resource["Properties"]["Instances"]["TerminationProtected"] = false
    resource["Properties"]["Instances"].delete("Placement")
    resource["Properties"]["Instances"].delete("HadoopVersion")
    subnet_id = Context.environment.subnet_ids(JsonTools.get(definition, "Properties.Instances.Ec2SubnetId", "@private"))[0]
    resource["Properties"]["Instances"]["Ec2SubnetId"] = subnet_id

    # Configure cluster configurations
    JsonTools.transfer(definition, "Properties.Configurations", resource)
    pipeline_configurations = []
    resource["Properties"]["Configurations"] ||= []

    proxy_host = Context.environment.variable("aws_proxy_host", nil)
    proxy_port = Context.environment.variable("aws_proxy_port", nil)
    unless proxy_host.nil? or proxy_port.nil?
      # Set cluster proxy settings
      no_proxy = Context.environment.variable("aws_no_proxy_wildcards", "")
      no_proxy = no_proxy.split(",").join("\\|")
      options = %W(
        -Dhttp.proxyHost=#{proxy_host}
        -Dhttp.proxyPort=#{proxy_port}
        -Dhttp.nonProxyHosts=#{no_proxy}
        -Dhttps.proxyHost=#{proxy_host}
        -Dhttps.proxyPort=#{proxy_port}
      ).join(" ")

      # Set proxy for Hadoop and Yarn in environment
      pipeline_configurations << {
        "Classification" => "hadoop-env",
        "Configurations" => [
          {
            "Classification" => "export",
            "ConfigurationProperties" => {
              "HADOOP_OPTS" => options,
              "YARN_OPTS" => options,
            }
          }
        ]
      }

      # Set proxy for mapreduce in Java options
      pipeline_configurations << {
        "Classification" => "mapred-site",
        "ConfigurationProperties" => {
          # TODO: these options override default memory settings - find a way to fix this.
          "mapreduce.map.java.opts" => options,
          "mapreduce.reduce.java.opts" => options,
        }
      }

    end

    # Enable EMRFS S3 SSE by default
    pipeline_configurations << {
      "Classification" => "emrfs-site",
      "ConfigurationProperties" => {
        "fs.s3.enableServerSideEncryption" => "true",
      }
    }

    # Merge user configuration with default configuration
    _merge_configurations(pipeline_configurations, resource["Properties"]["Configurations"])

    # Ensure exports are quoted - EMR doesn't automatically quote these
    _quote_exports(resource["Properties"]["Configurations"])

    # Configure cluster bootstrap actions
    artefact_bucket = Context.s3.artefact_bucket_name
    cd_artefact_path = Defaults.cd_artefact_path(component_name: component_name)
    bootstrap_actions = [
      {
        "Name" => "PipelineBootstrap",
        "ScriptBootstrapAction" => {
          "Args" => [
            "s3://#{artefact_bucket}/#{cd_artefact_path}",
          ],
          "Path" => "s3://#{artefact_bucket}/#{cd_artefact_path}/bootstrap.sh"
        }
      }
    ]

    bootstrap_actions += JsonTools.get(definition, "Properties.BootstrapActions", [])
    resource["Properties"]["BootstrapActions"] = bootstrap_actions

    template["Outputs"]["#{name}Id"] = {
      "Description" => "EMR cluster id",
      "Value" => { "Ref" => name }
    }

    template["Outputs"]["#{name}MasterPublicDNS"] = {
      "Description" => "EMR master public DNS",
      "Value" => { "Fn::GetAtt" => [name, "MasterPublicDNS"] }
    }

    # CloudFormation resource for EMR cluster does not currently provide master ip address attribute
    # The internal DNS name provided is only accessible from within the same VPC
    # Workaround below is used to derive ip address from the MasterPublicDNS attribute
    template["Outputs"]["#{name}MasterPrivateIp"] = {
      "Description" => "EMR Master Private Ip",
      "Value" => _sub_master_dns_for_ip(cluster: name)
    }
  end

  private

  def _log_uri(component_name)
    sections = Defaults.sections
    [
      "s3://#{Context.s3.as_bucket_name}/emr_logs",
      sections[:ase],
      sections[:branch],
      sections[:build],
      component_name
    ].join('/')
  end

  def _fq_name(component_name, name)
    sections = Defaults.sections
    [
      sections[:ams],
      sections[:qda],
      sections[:as],
      sections[:ase],
      sections[:branch],
      sections[:build],
      component_name,
      name,
    ].join('-')[0..128]
  end

  def _cluster_base_security_rules(component_name)
    [
      # Allow SSH
      IpSecurityRule.new(
        sources: Defaults.default_inbound_sources,
        destination: "#{component_name}.MasterSecurityGroup",
        ports: ['TCP:22'],
        allow_direct_sg: true
      ),
      # QCPP-1103 Allow Qualys full port access
      IpSecurityRule.new(
        sources: Defaults.default_qualys_sources,
        destination: "#{component_name}.MasterSecurityGroup",
        ports: "ALL:0-65535",
        allow_direct_sg: true,
      ),
      IpSecurityRule.new(
        sources: Defaults.default_qualys_sources,
        destination: "#{component_name}.SlaveSecurityGroup",
        ports: "ALL:0-65535",
        allow_direct_sg: true,
      ),
      # Allow access to CloudWatch metrics
      IamSecurityRule.new(
        roles: "#{component_name}.InstanceRole",
        actions: %w(
          elasticmapreduce:Describe*
          elasticmapreduce:List*
        ),
        resources: "*",
        condition: {
          "StringEquals" => {
            "elasticmapreduce:ResourceTag/Name" => Defaults.component_name_tag(
              component_name: component_name,
              build: Context.component.build_number(@component_name) || Defaults.sections[:build]
            )
          }
        }
      ),
      # Allow access to CloudWatch metrics
      IamSecurityRule.new(
        roles: "#{component_name}.InstanceRole",
        actions: %w(
          cloudwatch:PutMetricData
        ),
        resources: "*"
      ),
      # Allow instance to decrypt secrets using KMS
      IamSecurityRule.new(
        roles: "#{component_name}.InstanceRole",
        actions: %w(
          kms:Decrypt
          kms:DescribeKey
          kms:Encrypt
          kms:Generate*
          kms:ReEncrypt*
        ),
        resources: Context.kms.secrets_key_arn,
      ),
      # Bucket GetLocation access
      IamSecurityRule.new(
        roles: "#{component_name}.InstanceRole",
        actions: %w(
          s3:GetBucketLocation
        ),
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
        roles: "#{component_name}.InstanceRole",
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
        roles: "#{component_name}.InstanceRole",
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
        )
      ),
      # Bucket Write access
      IamSecurityRule.new(
        roles: "#{component_name}.InstanceRole",
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

  # Merge 'Configurations' property arrays
  # @param source_configurations [Hash] Source configuration definitions
  # @param dest_configurations [Hash] Destination configuration definitions
  def _merge_configurations(source_configurations, dest_configurations)
    source_configurations.each do |source_configuration|
      # Find all matching configuration objects
      matching = dest_configurations.select do |dest_configuration|
        dest_configuration["Classification"] == source_configuration["Classification"]
      end
      if matching.empty?
        # No matching classification - just add the new one in (no merge required)
        dest_configurations << source_configuration
      else
        dest_configuration = matching[-1]
        # Merge the ConfigurationProperties key
        (source_configuration["ConfigurationProperties"] || {}).each do |key, value|
          dest_configuration["ConfigurationProperties"] ||= {}

          # Append the new value to the old value
          if dest_configuration["ConfigurationProperties"][key].nil? or dest_configuration["ConfigurationProperties"][key].empty?
            # No key - set value
            dest_configuration["ConfigurationProperties"][key] = value
          elsif ["true", "false"].include? dest_configuration["ConfigurationProperties"][key].downcase
            # Boolean type - replace value
            dest_configuration["ConfigurationProperties"][key] = value
          elsif /^[0-9. ]+$/ === dest_configuration["ConfigurationProperties"]
            # Number type - replace value
            dest_configuration["ConfigurationProperties"][key] = value
          else
            # Other - append value
            dest_configuration["ConfigurationProperties"][key] += " #{value}"
          end
        end

        # Merge the Configurations key (recursive)
        if source_configuration.has_key? "Configurations"
          if dest_configuration.has_key? "Configurations"
            # Source and dest both have Configurations key - perform a recursive merge
            _merge_configurations(source_configuration["Configurations"], dest_configuration["Configurations"])
          else
            # Destination doesn't have a configurations key - just add in the new one (no merge required)
            dest_configuration["Configurations"] = source_configuration["Configurations"]
          end
        end
      end
    end
  end

  # Quote 'export' Configuration options - this is not done by EMR
  # @param configurations [Hash] Configuration definitions
  # @param level [FixNum] Starting level of recursive invocation
  def _quote_exports(configurations, level = 1)
    return if configurations.nil?
    return if level > 10

    configurations.each do |configuration|
      if configuration["Classification"] == "export"
        configuration["ConfigurationProperties"].each do |key, value|
          next if /^('.*')|(".*")$/ === value

          configuration["ConfigurationProperties"][key] = value.inspect
        end
      end

      # Recursively quote exports
      _quote_exports(configuration["Configurations"], level + 1)
    end
  end

  # Replace nested hash values matched to a pattern. Requires a block
  # @param input [Hash] Input hash definitions
  # @param pattern [String] Regex expression or a string for matching values
  def _replace_values(input, pattern, &block)
    raise "Method requires a block" unless block_given?

    case input
    when Hash
      input.each { |k, v| input[k] = _replace_values(v, pattern, &block) }
    when Array
      input.map { |v| _replace_values(v, pattern, &block) }
    else
      input.to_s.match(pattern) ? _replace_values(yield(input), pattern, &block) : input
    end
  end

  # Replace nested hash values matched to a pattern. Requires a block
  # @return [Hash] Returns CloudFormation expression for converting MasterPublicDNS attribute to Private IP
  def _sub_master_dns_for_ip(cluster: nil)
    {
      "Fn::Sub" => [
        "${Oct1}.${Oct2}.${Oct3}.${Oct4}", {
          "Oct1" => {
            "Fn::Select" =>
              [1, {
                "Fn::Split" => ["-", {
                  "Fn::Select" => [0, { "Fn::Split" => [".", { "Fn::GetAtt" => [cluster, "MasterPublicDNS"] }] }]
                }]
              }]
          },
          "Oct2" => {
            "Fn::Select" =>
              [2, {
                "Fn::Split" => ["-", {
                  "Fn::Select" => [0, { "Fn::Split" => [".", { "Fn::GetAtt" => [cluster, "MasterPublicDNS"] }] }]
                }]
              }]
          },
          "Oct3" => {
            "Fn::Select" =>
              [3, {
                "Fn::Split" => ["-", {
                  "Fn::Select" => [0, { "Fn::Split" => [".", { "Fn::GetAtt" => [cluster, "MasterPublicDNS"] }] }]
                }]
              }]
          },
          "Oct4" => {
            "Fn::Select" =>
              [4, {
                "Fn::Split" => ["-", {
                  "Fn::Select" => [0, { "Fn::Split" => [".", { "Fn::GetAtt" => [cluster, "MasterPublicDNS"] }] }]
                }]
              }]
          }
        }
      ]
    }
  end

  def _upload_cd_artefacts(
    component_name: nil,
    context_skip_keys: []
  )

    objects = {}

    Log.info "Creating bamboo environment variables file for use by the cluster"
    bamboo_variables = Context.environment.dump_variables

    bamboo_variables["pipeline_name"] = component_name
    objects["bamboo-vars.conf"] = ObjToText.generate_flat_config(
      variables: bamboo_variables.sort.to_h,
      line_prefix: "bamboo_",
      quote_strings: :special
    )

    Log.info "Creating context variables file for use by the instance"
    context_variables = Context.component.dump_variables(component_name, context_skip_keys)

    objects["context"] = ObjToText.generate_flat_config(
      variables: context_variables.sort.to_h,
      quote_strings: true,
      line_prefix: "export "
    )

    # Create QCP proxy set script
    objects["set_qcp_proxy.sh"] = UserData.process_file(
      "#{__dir__}/../common/linux/set_qcp_proxy.sh",
      "AwsProxy" => Context.environment.variable("aws_proxy", ""),
      "NoProxy" => Context.environment.variable("aws_no_proxy", "")
    )

    files = {
      "bootstrap.sh" => "#{__dir__}/../aws_emr_cluster/bootstrap.sh",
      "kms_decrypt.sh" => "#{__dir__}/../common/linux/kms_decrypt.sh",
      "kms_decrypt_file.sh" => "#{__dir__}/../common/linux/kms_decrypt_file.sh",
      "kms_encrypt.sh" => "#{__dir__}/../common/linux/kms_encrypt.sh",
      "kms_encrypt_file.sh" => "#{__dir__}/../common/linux/kms_encrypt_file.sh",
      "put_metric.sh" => "#{__dir__}/../common/linux/put_metric.sh"
    }

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
end
