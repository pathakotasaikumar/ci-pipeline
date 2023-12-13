require_relative "aws/builders/security_item_builder"
require_relative "aws/builders/security_rule_builder"
require_relative "aws/builders/managed_policy_builder"

class AsirSecurity
  extend SecurityItemBuilder
  extend SecurityRuleBuilder
  extend ManagedPolicyBuilder

  @@default_poll_time = 5.0

  # poll time in seconds for the thread to update ASIR rule stacks
  # @return (Integer) 5 second by default
  def self.security_stack_update_poll_time
    @@default_poll_time
  end

  def self.deploy_security_items
    set_name = Context.asir.set_name

    # Create/Retrieve ASIR destination security group (one per AS-environment)
    asir_dest_sg_id = Context.asir.destination_sg_id
    _deploy_asir_destination_sg if asir_dest_sg_id.nil?

    # Create/Retrieve ASIR source security group (one per AS-environment-set)
    asir_source_sg_id = Context.asir.source_sg_id(set_name)
    _deploy_asir_source_sg(set_name) if asir_source_sg_id.nil?

    # Create ASIR destination security rules stack
    rules_stack_id = Context.asir.destination_rules_stack_id
    _deploy_asir_rules_stack if rules_stack_id.nil?

    # Create ASIR managed policy
    managed_policy_arn = Context.asir.managed_policy_arn(set_name)
    _deploy_asir_managed_policy(set_name) if managed_policy_arn.nil?

    ams_iam_policy_arn = _find_ams_iam_policy
    Context.asir.set_ams_iam_policy_arn(ams_iam_policy_arn,"QCPAMSManagedPolicyArn")
  end

  def self.deploy_security_rules
    set_name = Context.asir.set_name
    sections = Defaults.sections

    # Find all destination apps referencing this source set
    app_id = "#{sections[:ams].upcase}-#{sections[:qda].upcase}-#{sections[:as].upcase}-#{sections[:env].upcase}"
    set_id = "#{sections[:ams].upcase}-#{sections[:qda].upcase}-#{sections[:as].upcase}-#{sections[:env].upcase}-#{set_name}"
    rules = _rules_in_set(set_id)
    destination_app_ids = rules.map { |rule| rule["destination"] } + [app_id]
    destination_app_ids = destination_app_ids.uniq.sort

    thread_items = []
    destination_app_ids.each do |destination_app_id|
      ams, qda, as, env = destination_app_id.downcase.split("-")
      if ams.nil? or ams.empty? or qda.nil? or qda.empty? or as.nil? or as.empty? or env.nil? or env.empty?
        Log.warn "Could not extract app details from destination application id #{destination_app_id.inspect} - skipping rules update"
        next
      end
      destination_sections = { ams: ams, qda: qda, as: as, env: env }

      # Lookup the destination ASIR rules stack id
      rules_stack_id = Context.asir.destination_rules_stack_id(destination_sections)
      if rules_stack_id.nil?
        Log.debug "Cannot find ASIR rules stack for destination #{destination_app_id.inspect}, destination may not have been built yet - skipping rules update"
        next
      end

      # Lookup the destination ASIR security group id
      destination_sg_id = Context.asir.destination_sg_id(destination_sections)
      if destination_sg_id.nil?
        Log.debug "Cannot find ASIR security group for destination #{destination_app_id.inspect}, destination may not have been built yet - skipping rules update"
        next
      end

      # Retrieve all rules that apply to this destination app
      destination_rules = _rules_with_destination(destination_app_id)

      # Generate rules stack template for this destination app
      template = _build_rules_template(destination_sg_id, destination_rules)

      # Update the destination rules stack
      current_template = Context.asir.destination_rules_template(destination_sections)
      if current_template == template
        Log.debug "No update required to #{destination_app_id.inspect} ASIR rules stack"
      else
        thread_items << {
          "destination_app_id" => destination_app_id,
          "thread" => Thread.new {
            Log.debug "Updating #{destination_app_id.inspect} ASIR rules stack with new template"
            outputs = AwsHelper.cfn_update_stack(stack_name: rules_stack_id, template: template)
            Context.asir.set_destination_rules_details(outputs["StackId"], template, destination_sections)
          }
        }
      end
    end

    Log.debug "Updating ASIR rules stack with new template, poll time in sec: #{security_stack_update_poll_time}"
    successful, failed = ThreadHelper.wait_for_threads(thread_items, security_stack_update_poll_time)

    failed.each do |failed_thread|
      Log.error "Failed to update ASIR rules stack for application #{failed_thread['destination_app_id'].inspect} - #{failed_thread['exception']}"
    end
  end

  def self._deploy_asir_destination_sg
    stack_name = Defaults.asir_destination_group_stack_name
    stack_id = AwsHelper.cfn_stack_exists(stack_name)
    if stack_id.nil?
      Log.info "Creating ASIR Destination stack"
      template = { "Resources" => {}, "Outputs" => {} }
      _process_security_items(
        template: template,
        vpc_id: Context.environment.vpc_id,
        security_items: [{ "Name" => "AsirDestinationGroup", "Type" => "SecurityGroup" }]
      )
      begin
        tags = Defaults.get_tags("AsirDestinationGroup", :env)
        outputs = AwsHelper.cfn_create_stack(
          stack_name: stack_name,
          template: template,
          tags: tags,
          wait_delay: 10
        )
        Context.asir.set_destination_details(outputs["StackId"], outputs["AsirDestinationGroupId"])
      rescue ActionError => e
        Context.asir.set_destination_details(e.partial_outputs["StackId"], e.partial_outputs["AsirDestinationGroupId"])
        raise "Failed to create ASIR destination stack - #{e}"
      rescue => e
        raise "Failed to create ASIR destination stack - #{e}"
      end
    else
      Log.info "Loading ASIR Destination SG details"
      begin
        outputs = AwsHelper.cfn_get_stack_outputs(stack_id)
        raise "Stack did not output an ASIR Destination SG id" if outputs["AsirDestinationGroupId"].nil?

        Context.asir.set_destination_details(stack_id, outputs["AsirDestinationGroupId"])
      rescue => e
        raise "An error occurred loading ASIR Destination SG details - #{e}"
      end
    end
  end

  def self._deploy_asir_source_sg(set_name)
    stack_name = Defaults.asir_source_group_stack_name(set_name)
    stack_id = AwsHelper.cfn_stack_exists(stack_name)
    if stack_id.nil?
      Log.info "Creating ASIR Source stack"
      template = { "Resources" => {}, "Outputs" => {} }
      _process_security_items(
        template: template,
        vpc_id: Context.environment.vpc_id,
        security_items: [{ "Name" => "AsirSourceGroup", "Type" => "SecurityGroup" }]
      )
      begin
        tags = Defaults.get_tags("#{set_name}-AsirSourceGroup", :env)
        outputs = AwsHelper.cfn_create_stack(
          stack_name: stack_name,
          template: template,
          tags: tags,
          wait_delay: 10
        )
        Context.asir.set_source_details(set_name, outputs["StackId"], outputs["AsirSourceGroupId"])
      rescue ActionError => e
        Context.asir.set_source_details(set_name, e.partial_outputs["StackId"], e.partial_outputs["AsirSourceGroupId"])
        raise "Failed to create ASIR source stack - #{e}"
      rescue => e
        raise "Failed to create ASIR source stack - #{e}"
      end
    else
      Log.info "Loading ASIR Source SG details"
      begin
        outputs = AwsHelper.cfn_get_stack_outputs(stack_id)
        raise "Stack did not output an ASIR Source SG id" if outputs["AsirSourceGroupId"].nil?

        Context.asir.set_source_details(set_name, stack_id, outputs["AsirSourceGroupId"])
      rescue => e
        raise "An error occurred loading ASIR Source SG details - #{e}"
      end
    end
  end

  def self._deploy_asir_managed_policy(set_name)
    # Currently not implemented in ASIR - manually managed by CSI. Set set_name accordingly.
    set_name = "manual"

    stack_name = Defaults.asir_managed_policy_stack_name(set_name)
    stack_id = AwsHelper.cfn_stack_exists(stack_name)
    if stack_id.nil?
      Log.info "Creating ASIR Source stack"
      template = { "Resources" => {}, "Outputs" => {} }
      _process_managed_policy(
        template: template,
        policy_definition: { "AsirManagedPolicy" => {} }
      )
      begin
        tags = Defaults.get_tags("AsirManagedPolicy", :env)

        outputs = AwsHelper.cfn_create_stack(
          stack_name: stack_name,
          template: template,
          tags: tags,
          wait_delay: 15
        )
        Context.asir.set_managed_policy_details(set_name, outputs["StackId"], outputs["AsirManagedPolicyArn"])
      rescue ActionError => e
        Context.asir.set_managed_policy_details(set_name, e.partial_outputs["StackId"], e.partial_outputs["AsirManagedPolicyArn"])
        raise "Failed to create ASIR source stack - #{e}"
      rescue => e
        raise "Failed to create ASIR source stack - #{e}"
      end
    else
      Log.info "Loading ASIR managed policy details"
      begin
        outputs = AwsHelper.cfn_get_stack_outputs(stack_id)
        raise "Stack did not output an ASIR managed policy ARN" if outputs["AsirManagedPolicyArn"].nil?

        Context.asir.set_managed_policy_details(set_name, stack_id, outputs["AsirManagedPolicyArn"])
      rescue => e
        raise "An error occurred loading ASIR managed policy details - #{e}"
      end
    end
  end

  def self._deploy_asir_rules_stack
    stack_name = Defaults.asir_destination_rules_stack_name
    stack_id = AwsHelper.cfn_stack_exists(stack_name)
    if stack_id.nil?
      Log.info "Creating new ASIR Destination rules stack"
      template = {
        "Resources" => {
          "NoRules" => {
            "Type" => "AWS::CloudFormation::WaitConditionHandle",
            "Properties" => {},
          }
        }
      }
      begin
        tags = Defaults.get_tags("AsirDestinationRules", :env)
        outputs = AwsHelper.cfn_create_stack(
          stack_name: stack_name,
          template: template,
          tags: tags,
          wait_delay: 10
        )
        Context.asir.set_destination_rules_details(outputs["StackId"], template)
      rescue => e
        raise "Failed to create ASIR destination rules stack - #{e}"
      end
    else
      Log.info "Loading ASIR Rules details"
      template = AwsHelper.cfn_get_template(stack_id)
      Context.asir.set_destination_rules_details(stack_id, template)
    end
  end

  def self._build_rules_template(destination_sg_id, destination_rules)
    rules = []
    destination_rules.each do |rule|
      asir_set = rule["asir_set"]
      rule_id = rule["rule_id"]
      protocol = rule["protocol"]
      port = rule["port"]
      source = rule["source"]

      if source[0..0] !~ /[0-9]/
        # Source is an application service - lookup the source ASIR security group id
        ams, qda, as, env = source.downcase.split("-")
        source_sections = { ams: ams, qda: qda, as: as, env: env }
        set_name = asir_set.split("-")[4..-1].join("-")
        source_lookup = Context.asir.source_sg_id(set_name, source_sections)
        if source_lookup.nil?
          Log.debug "Cannot find ASIR security group for source #{source.inspect} - skipping this rule"
          next
        else
          source = source_lookup
        end
      end

      rules << IpSecurityRule.new(
        sources: source,
        destination: destination_sg_id,
        ports: "#{protocol}:#{port}",
        name: "#{asir_set}-#{rule_id}",
        allow_cidr: true,
        allow_direct_sg: true,
      )
    end

    template = { "Resources" => {} }

    _process_security_rules(
      template: template,
      rules: rules,
    )

    # Create a stub template if there are no ASIR rules
    if template["Resources"].empty?
      template["Resources"]["NoRules"] = {
        "Type" => "AWS::CloudFormation::WaitConditionHandle",
        "Properties" => {},
      }
    end

    return template
  end

  # Query for all of the rules in the specified set
  def self._rules_in_set(asir_set)
    response = AwsHelper.dynamodb_query(
      table_name: Context.asir.dynamo_table,
      condition: "asir_set = :asir_set",
      filter: "attribute_not_exists(disabled)",
      expression_attribute_values: {
        ":asir_set" => asir_set,
      }
    )

    return response.items
  end

  # Query for all of the rules with the specified destination
  def self._rules_with_destination(app_service_id)
    response = AwsHelper.dynamodb_query(
      table_name: Context.asir.dynamo_table,
      index_name: "destination-rule_id-index",
      filter: "attribute_not_exists(disabled)",
      condition: "destination = :app_service_id",
      expression_attribute_values: {
        ":app_service_id" => app_service_id,
      }
    )

    return response.items
  end

  def self._find_ams_iam_policy
    begin
      ams_iam_arn = AwsHelper.cfn_get_stack_outputs(Defaults.qcp_iam_ams_managed_stack_name)["QCPAMSManagedPolicyArn"]
    rescue => e
      Log.warn("QCP AMS IAM rules could not be found: #{e}")
      # TODO: Should this break the build?  Given permissions are required.. I say yes
      # Capturing the error here to allow more useful logging, but also causing execution to fail
      raise e
    end
    return ams_iam_arn
  end
end
