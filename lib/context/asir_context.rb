class AsirContext
  def initialize(state_storage, sections)
    @state_storage = state_storage
    @default_sections = sections

    @set_name = nil

    @dynamo_context = nil
    @destination_context = {}
    @source_context = {}
    @policy_context = {}
    @rules_context = {}
    @qcp_rules_arns = {}
  end

  # Pipeline Bucket
  def set_dynamo_table_details(table_name)
    @dynamo_context = {
      'Table' => table_name
    }
  end

  def dynamo_table
    return @dynamo_context['Table']
  end

  def set_name
    return @set_name
  end

  def set_name=(set_name)
    @set_name = set_name
  end

  def set_destination_details(stack_id, security_group_id, sections = @default_sections)
    path = _destination_context_path(sections)
    @destination_context[path] = {
      'StackId' => stack_id,
      'SecurityGroupId' => security_group_id,
    }
    @state_storage.save(path, @destination_context[path])
    if sections.eql? @default_sections
      Context.component.set_variables("_asir", {
        "DestinationStackId" => stack_id,
        "DestinationSecurityGroupId" => security_group_id
      })
    end
  end

  def destination_stack_id(sections = @default_sections)
    return _destination_context(sections)['StackId']
  end

  def destination_account_id(sections = @default_sections)
    stack_id = _destination_context(sections)['StackId']
    return nil if stack_id.nil?

    return stack_id.split(':')[4]
  end

  def destination_sg_id(sections = @default_sections)
    return _destination_context(sections)['SecurityGroupId']
  end

  def set_destination_rules_details(stack_id, template, sections = @default_sections)
    path = _rules_context_path(sections)
    @rules_context[path] = {
      'StackId' => stack_id,
      'Template' => template,
    }
    @state_storage.save(path, @rules_context[path])
  end

  def destination_rules_stack_id(sections = @default_sections)
    return _rules_context(sections)['StackId']
  end

  def destination_rules_template(sections = @default_sections)
    return _rules_context(sections)['Template']
  end

  def set_source_details(set_name, stack_id, security_group_id, sections = @default_sections)
    path = _source_context_path(sections, set_name)
    @source_context[path] = {
      'StackId' => stack_id,
      'SecurityGroupId' => security_group_id,
    }
    @state_storage.save(path, @source_context[path])
    if sections.eql? @default_sections
      Context.component.set_variables("_asir", {
        "SourceStackId" => stack_id,
        "SourceSecurityGroupId" => security_group_id
      })
    end
  end

  def source_stack_id(set_name = nil, sections = @default_sections)
    set_name ||= Context.asir.set_name
    return _source_context(sections, set_name)['AwsAccountId']
  end

  def source_account_id(sections = @default_sections)
    stack_id = _source_context(sections, set_name)['StackId']
    return nil if stack_id.nil?

    return stack_id.split(':')[4]
  end

  def source_sg_id(set_name = nil, sections = @default_sections)
    set_name ||= Context.asir.set_name
    return _source_context(sections, set_name)['SecurityGroupId']
  end

  def set_managed_policy_details(set_name, stack_id, policy_arn, sections = @default_sections)
    # TODO: remove once ASIR managed the policies
    set_name = "manual"

    path = _policy_context_path(sections, set_name)
    @policy_context[path] = {
      "StackId" => stack_id,
      "PolicyArn" => policy_arn,
    }
    @state_storage.save(path, @policy_context[path])
  end

  def managed_policy_arn(set_name = nil, sections = @default_sections)
    # TODO: remove once ASIR manages the policies
    set_name = "manual"

    set_name ||= Context.asir.set_name
    return _policy_context(sections, set_name)["PolicyArn"]
  end

  # @return Array of managed policies
  def managed_policy_arn_list
    arns = []
    arns << managed_policy_arn
    arns << @qcp_rules_arns["QCPAMSManagedPolicyArn"] if @qcp_rules_arns.key?("QCPAMSManagedPolicyArn")
  end

  def set_ams_iam_policy_arn(arn, name)
    @qcp_rules_arns[name] = arn if not (name.nil? || name.empty?)
  end


  def flush
    # Not required - performed on every write
  end

  private def _destination_context(sections)
    path = _destination_context_path(sections)
    @destination_context[path] ||= (@state_storage.load(path) || {})
    if sections.eql? @default_sections
      Context.component.set_variables("_asir", {
        "DestinationStackId" => @destination_context[path]['StackId'],
        "DestinationSecurityGroupId" => @destination_context[path]['SecurityGroupId']
      })
    end
    return @destination_context[path]
  end

  private def _source_context(sections, set_name)
    path = _source_context_path(sections, set_name)
    @source_context[path] ||= (@state_storage.load(path) || {})
    if sections.eql? @default_sections
      Context.component.set_variables("_asir", {
        "SourceStackId" => @source_context[path]['StackId'],
        "SourceSecurityGroupId" => @source_context[path]['SecurityGroupId']
      })
    end
    return @source_context[path]
  end

  private def _policy_context(sections, set_name)
    path = _policy_context_path(sections, set_name)
    @policy_context[path] ||= (@state_storage.load(path) || {})
    return @policy_context[path]
  end

  private def _rules_context(sections)
    path = _rules_context_path(sections)
    @rules_context[path] ||= (@state_storage.load(path) || {})
    return @rules_context[path]
  end

  private def _destination_context_path(sections)
    return [sections[:ams], sections[:qda], sections[:as], 'env-' + sections[:env], 'AsirDestinationGroup']
  end

  private def _rules_context_path(sections)
    return [sections[:ams], sections[:qda], sections[:as], 'env-' + sections[:env], 'AsirDestinationRules']
  end

  private def _source_context_path(sections, set_name)
    return [sections[:ams], sections[:qda], sections[:as], 'env-' + sections[:env], set_name, 'AsirSourceGroup']
  end

  private def _policy_context_path(sections, set_name)
    return [sections[:ams], sections[:qda], sections[:as], 'env-' + sections[:env], set_name, 'AsirManagedPolicy']
  end
end
