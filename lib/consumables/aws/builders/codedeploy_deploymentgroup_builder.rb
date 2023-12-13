# Module creates  CloudFormation templates for CodeDeploy DeploymentGroup
module AwsCodeDeployDeploymentGroupBuilder
  # Creates a CloudFormation template for a new CodeDeploy application
  # @param template [Hash] CloudFormation template passed in as reference
  # @param resource_name [String] CloudFormation template resource name
  # @param custom_resource_name [String] custom name for CloudFormation resource, allows to have many resources under the same stack
  # @param definition [Hash] Pipeline YAML component definition
  # @param application_name [String] CodeDeploy application name
  # @param service_role_arn [String] CodeDeploy service role ARN
  # @param s3_location [Hash] S3 location for revision deployment, hash similar to S3Location AWS object
  # @param ec2_tag_filters [Hash] ec2 tags to target revision deployment
  # @param autoscaling_group_names [Array] autoscaling group names to target revision deployment
  # @param deployment_group_name [String] CodeDeploy Deployment group name
  # @param deployment_style [Hash] Codedeploy Deployment style
  # @param load_balancer_info [Hash]Array Hash of arrays matching LoadBalancerInfo
  def _process_codedeploy_deployment_group(
    template:,
    resource_name:,
    custom_resource_name:,
    definition:,
    application_name:,
    service_role_arn:,
    ec2_tag_filters: nil,
    autoscaling_group_names: nil,
    deployment_group_name:,
    deployment_style: {},
    load_balancer_info: {}
  )
    # Substituting variables (stack references and outputs, etc.) into component definition
    Context.component.replace_variables(definition)

    # use either of resource_name or aws_resource_name
    # that way, we can have multiple resources under the same stack
    # CodeDeploy uses it to store all revisions within one AWS stack
    aws_resource_name = resource_name

    if (custom_resource_name != nil)
      aws_resource_name = custom_resource_name
    end

    # create top level resource
    resource = {
      "Type" => "AWS::CodeDeploy::DeploymentGroup",
      "Properties" => JsonTools.get(definition[resource_name], "Properties", {}),
    }

    template["Resources"][aws_resource_name] = resource

    resource["Properties"] = {} unless resource["Properties"].nil?
    resource_properties = resource["Properties"]

    # override system level props, point to the right app and security
    resource_properties["DeploymentGroupName"] = deployment_group_name
    resource_properties["ApplicationName"] = application_name
    resource_properties["ServiceRoleArn"] = service_role_arn

    # override deployment, always empty
    # we trigger deplouyment via API later
    resource_properties.delete("Deployment")

    # EC2 instance targeting - update tags
    if !ec2_tag_filters.nil?
      resource_properties['Ec2TagFilters'] = _create_ec2_tags(ec2_tag_filters: ec2_tag_filters)
    end

    # AutoScale group targeting
    if !autoscaling_group_names.nil?
      resource_properties['AutoScalingGroups'] = _create_autoscale_target(autoscaling_group_names: autoscaling_group_names)
    end

    # Deployment method used when targets are behind load balancer
    if !deployment_style.empty?
      resource_properties['DeploymentStyle'] = _create_deploymentstyle(deployment_style: deployment_style)
    end

    # Load balancer that targets will be removed from
    if !load_balancer_info.empty?
      # Ensuring WITH_TRAFFIC_CONTROL is set to avoid load balancer info being ignored
      if !deployment_style.has_value?('WITH_TRAFFIC_CONTROL')
        raise "Deployment option WITH_TRAFFIC_CONTROL is required for load balancer info to be used, please add correct deployment option to component definition"
      end

      resource_properties['LoadBalancerInfo'] = _create_loadbalancerinfo(load_balancer_info: load_balancer_info)
    end

    template
  end

  # Creates and validate AutoScalingGroups array
  # @param ec2_tag_filters [Array] Array of string to use as "AutoScalingGroups"
  # @return [Array] Array of strings to as "AutoScalingGroups"
  def _create_autoscale_target(autoscaling_group_names:)
    if (autoscaling_group_names.nil? || autoscaling_group_names.count == 0)
      raise "AutoScale Group names are nil or empty: #{autoscaling_group_names}"
    end

    autoscaling_group_names
  end

  # Creates and validates DeploymentStyle hash
  # @param deployment_style hash
  # @return hash to use for deployment_style
  def _create_deploymentstyle(deployment_style:)
    if (!deployment_style.key?('DeploymentOption') && !deployment_style.key?('DeploymentType'))
      raise "Expecting either DeploymentOption or DeploymentType, no valid style specified"
    end

    deployment_style
  end

  # Creates and validates LoadBalancerInfo array
  # @param LoadBalancerInfo hash[Array]
  # @return hash[Array] Hash of arrays to use for LoadBalancerInfo
  def _create_loadbalancerinfo(load_balancer_info:)
    if (!load_balancer_info.key?('ElbInfoList') && !load_balancer_info.key?('TargetGroupInfoList'))
      raise "ElbInfoList or TargetGroupInfoList must be specified"
    end

    load_balancer_info
  end

  # Creates Ec2TagFilters array
  # @param ec2_tag_filters [Array] Array of hashes, similar to AWS's Ec2TagFilters
  # @return [Array] Array of hashes to use as "Ec2TagFilters"
  def _create_ec2_tags(ec2_tag_filters:)
    result = []

    ec2_tag_filters.each do |tag|
      type = 'KEY_AND_VALUE'
      type = tag['Type'].upcase unless tag['Type'].nil?

      raise "'Key' is nil for ec2_tag_filter value:[#{tag}]" if tag['Key'].nil?
      raise "'Value' is nil for ec2_tag_filter value:[#{tag}]" if tag['Value'].nil?

      result << {
        'Key' => tag['Key'],
        'Value' => tag['Value'],
        'Type' => type
      }
    end

    result
  end
end
