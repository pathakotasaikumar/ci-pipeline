require 'context_class'

class EnvironmentContext
  def initialize(state_storage, sections)
    @state_storage = state_storage
    @context = {}

    @context_path = _context_path(sections)

    if Defaults.is_cd_pipeline_task?
      Log.debug "Fetching pipeline SSM parameters under pipeline CD task: #{Defaults.pipeline_task}"
      _load_pipeline_parameters
    else
      Log.debug "Skipping pipeline SSM parameters under pipeline non-CD task: #{Defaults.pipeline_task}"
    end

    _load_environment_variables
  end

  def _load_pipeline_parameters
    begin
      # fail faster under unit tests, skipping timouts to create real clients
      # we don't use Context.environment.variable as it isn't available this time over Rake tasks initialization
      # would result in "uninitialized constant EnvironmentContext::Context" error
      raise 'Unable to obtain parameters under unit test workload' if ENV['local_pipeline_unit_testing'] == 'true'

      Log.info "Fetching pipeline SSM parameters, pipeline task: #{Defaults.pipeline_task}"
      prefix = Defaults.pipeline_parameter_prefix

      Log.debug "SSM path path used: #{prefix}"

      parameters = AwsHelper.ssm_get_parameters_by_path(
        path: prefix,
        recursive: false,
        with_decryption: true
      ).sort_by { |p| p.name }

      Log.debug "Fetched #{parameters.map.count} parameters under path #{prefix}"

      variables = {}
      parameters.map do |parameter|
        context_key = parameter.name.sub("#{prefix}/", '')
        Log.debug "Setting pipeline parameter: #{context_key}"
        variables[context_key] = parameter.value
      end

      set_variables(variables)
    rescue => e
      Log.error "Unable to fetch pipeline secret parameters, build will continue but deployment might fail - #{e}"
    ensure
      Log.info  "Fetching pipeline SSM parameters finished"
    end
  end

  def _load_environment_variables
    # Map bamboo variables into the context
    Log.info "Populating environment context from current environment"
    environment_variables = ENV.sort.inject({}) do |memo, (key, value)|
      if key.start_with? "bamboo_"
        context_key = key.sub("bamboo_", "")
        Log.debug "Overriding parameter: #{context_key} with an environment variable" unless variable(context_key, nil).nil?
        memo[context_key] = value
      end
      memo
    end

    set_variables(environment_variables)

    # Set additional proxy variables
    proxy = variable("aws_proxy", nil)

    unless proxy.nil?
      require "uri"
      uri = URI.parse(proxy)
      unless uri.host.nil?
        variables = {
          'aws_proxy_host' => uri.host,
          'aws_proxy_port' => uri.port || "3128",
          'aws_no_proxy' => %W(
            127.0.0.1
            169.254.169.254
            localhost.localdomain
            localhost
            s3-ap-southeast-2.amazonaws.com
            .s3-ap-southeast-2.amazonaws.com
            s3.ap-southeast-2.amazonaws.com
            .s3.ap-southeast-2.amazonaws.com
            s3.amazonaws.com
            .s3.amazonaws.com
            .#{Defaults.ad_dns_zone}
            .#{Defaults.r53_dns_zone}
            dynamodb.ap-southeast-2.amazonaws.com
            .dynamodb.ap-southeast-2.amazonaws.com
            cloudformation.ap-southeast-2.amazonaws.com
            kinesis.ap-southeast-2.amazonaws.com
            ssm.ap-southeast-2.amazonaws.com
            ec2.ap-southeast-2.amazonaws.com
            ec2messages.ap-southeast-2.amazonaws.com
            config.ap-southeast-2.amazonaws.com
            kms.ap-southeast-2.amazonaws.com
            monitoring.ap-southeast-2.amazonaws.com
            sns.ap-southeast-2.amazonaws.com
            sqs.ap-southeast-2.amazonaws.com
            api.qantas.com.au
            api-stg.qantas.com.au
            .ap-southeast-2.opsworks-cm.io
          ).join(','),
          'aws_no_proxy_wildcards' => %W(
            127.0.0.1
            10.*
            192.168.*
            169.254.*
            localhost.localdomain
            localhost
            s3-ap-southeast-2.amazonaws.com
            *.s3-ap-southeast-2.amazonaws.com
            s3.ap-southeast-2.amazonaws.com
            *.s3.ap-southeast-2.amazonaws.com
            s3.amazonaws.com
            *.s3.amazonaws.com
            *.#{Defaults.ad_dns_zone}
            *.#{Defaults.r53_dns_zone}
            dynamodb.ap-southeast-2.amazonaws.com
            *.dynamodb.ap-southeast-2.amazonaws.com
            cloudformation.ap-southeast-2.amazonaws.com
            kinesis.ap-southeast-2.amazonaws.com
            ssm.ap-southeast-2.amazonaws.com
            ec2.ap-southeast-2.amazonaws.com
            ec2messages.ap-southeast-2.amazonaws.com
            config.ap-southeast-2.amazonaws.com
            kms.ap-southeast-2.amazonaws.com
            monitoring.ap-southeast-2.amazonaws.com
            sns.ap-southeast-2.amazonaws.com
            sqs.ap-southeast-2.amazonaws.com
            api.qantas.com.au
            api-stg.qantas.com.au
            .ap-southeast-2.opsworks-cm.io
          ).join(',')
        }
        set_variables(variables)
      end
    end
  end

  def _context_path(sections)
    [
      sections[:ams],
      sections[:qda],
      sections[:as],
      sections[:ase],
      sections[:branch],
      sections[:build],
      'Environment'
    ]
  end

  def variable(variable_name, default = :undef)
    return @context[variable_name] if @context.has_key? variable_name
    return default unless default == :undef

    raise "Could not find environment variable #{variable_name}, and no default was supplied."
  end

  def variables
    return @context.clone
  end

  def set_variables(variables)
    list_variables = %w(
      ad_domain_list
      persist_true
      persist_false
      shared_accounts
      sns_source_accounts
      log_destination_source_accounts
    )
    variables.each do |key, value|
      if value.is_a?(String)
        value = value.strip
      end

      if key == 'soe_ami_ids'
        value = JSON.parse(value)
        raise "Expected Hash for #{key.inspect}, but received #{value.class.inspect}" unless value.is_a? Hash
      elsif list_variables.include? key
        value = value.delete(' ').split(',')
      end

      @context[key] = value
    end
  end

  def region
    return @context['aws_region'].downcase || "ap-southeast-2"
  end

  def account_id
    raise "AWS account id has not been defined - set variable aws_account_id" unless @context.has_key? 'aws_account_id'

    return @context['aws_account_id']
  end

  def vpc_id
    raise "AWS VPC id has not been defined - set variable aws_vpc_id" unless @context.has_key? 'aws_vpc_id'

    return @context['aws_vpc_id'].downcase
  end

  def dr_account_id
    raise "AWS DR Account id  has not been defined - set variable dr_account_id" unless @context.has_key? 'dr_account_id'

    return @context['dr_account_id'].downcase
  end

  def nonp_account_id
    environment = Defaults.sections[:env]
    if environment.downcase == "prod"
      raise "AWS NonProd Account id should be defined for Prod Plan - set variable nonp_account_id" unless @context.has_key? 'nonp_account_id'

      return @context['nonp_account_id'].downcase
    else
      unless @context['nonp_account_id'].nil?
        return @context['nonp_account_id'].downcase
      end
    end
  end

  # Checks whether this is in a QA environment
  # Some logic that depends on env in prod should also switch if it is in QA
  def qa?
    # From all entries, looks like it could be both boolean (false/true) and int (0/1)
    pipeline_qa = @context.fetch('pipeline_qa', 'false').to_s.downcase
    if pipeline_qa == "true" || pipeline_qa == "1"
      return true
    else
      return false
    end
  end

  # Checks whether we are in an experimental mode, defaults to QA
  # Some features needs to be flagged that only certain plans have access to
  def experimental?
    pipeline_experimental = @context.fetch('pipeline_experimental', 'false').to_s.downcase
    if pipeline_experimental == "true" || pipeline_experimental == "1"
      return true
    else
      return qa?
    end
  end

  # Function to retreive the subnet ids
  # @param name [String] alias for the subnet
  # @param filter [Hash] filter
  def subnets(name, filter = {})
    subnets = Context.environment.variable('aws_subnet_ids', nil)
    if subnets.nil?
      subnets = AwsHelper.ec2_get_subnets(vpc_id: Context.environment.vpc_id)
      Context.environment.set_variables({ 'aws_subnet_ids' => subnets })
    end

    filter_subnets = {}
    # Select subnets which match the alias
    name.split(",").each do |name|
      name = name.downcase.strip
      name = name[1..-1] if name.start_with? '@'
      subnets.each do |subnet_name, subnet|
        filter_subnets[subnet_name] = subnet if subnet_name.downcase.end_with? name.downcase
      end
    end

    raise "Could not find any subnets for alias #{name.inspect}" if filter_subnets.empty?

    # Filter selected subnets (all filters must match)
    filter_subnets = filter_subnets.select do |subnet_name, subnet|
      filter.all? { |key, value| subnet[key] == value }
    end
    raise "Could not find any subnets for alias #{name.inspect} matching filter #{filter.inspect}" if filter_subnets.empty?

    return filter_subnets
  end

  # Selects subnets based on the selection scheme
  # @param name [String] String used for matching subnets
  # @param filter [Hash] Filters to be applied for subnet list
  # @param scheme [Symbol] Subnet selection scheme
  #   :best_subnet_per_az = selects max 1 subnet per availability zone with lowest number of IPs
  #   :basic = select all available subnets
  def subnet_ids(name, filter = {}, scheme = :best_subnet_per_az)
    subnet_list = self.subnets(name, filter).values

    case scheme
    when :best_subnet_per_az
      subnet_map = _filter_best_subnet_per_az(subnet_list)
    when :basic
      subnet_map = subnet_list
    else
      raise "Unknown subnet selection scheme \"#{scheme}\" selected"
    end

    return subnet_map.values.map { |subnet| subnet[:id] }
  end

  def availability_zones(name)
    zones = Context.environment.variable('aws_availability_zones', nil)
    if zones.nil?
      zones = AwsHelper.ec2_get_availability_zones
      Context.environment.set_variables({ 'aws_availability_zones' => zones })
    end

    name = name.downcase
    name = name[1..-1] if name.start_with? '@'
    zones = zones.select { |zone| zone.downcase.end_with? name.downcase }
    raise "Cannot find availability zones for alias #{name.inspect}" if zones.empty?

    return zones
  end

  def persist_override(component_name, component_persist_setting)
    return true if (@context['persist_true'] || []).include? component_name
    return false if (@context['persist_false'] || []).include? component_name

    return (component_persist_setting == "true" or component_persist_setting == true)
  end

  # @return [Hash] Filtered list of variables and values
  def dump_variables
    Log.info "Creating environment variables file for use by the instance"
    skip_keys = %w(
      asir_
      agent_proxy
      aws_account_id
      aws_region
      aws_control_role
      aws_provisioning_role
      aws_availability_zones
      aws_subnet_ids
      pipeline_bucket_name
      legacy_bucket_name
      artefact_bucket_name
      lambda_artefact_bucket_name
      snow_
      soe_ami_ids
      splunk_
      api_gateway_
    )

    # Return save list of variables
    variables.inject({}) do |memo, (key, value)|
      next memo if skip_keys.any? { |skip_key| key.include? skip_key }

      memo[key] = value
      memo
    end
  end

  def flush
    Log.info "Saving environment context"
    @state_storage.save(@context_path, @context)
  end

  private

  # @param subnet_list [List] List of hahses for subnets with name of the subnet as the key
  # @return [Hash] Filtered list of Hashes for best subnet per az.
  def _filter_best_subnet_per_az(subnet_list)
    best_subnet_per_az = {}
    Log.debug "Selecting best subnets from a list: #{subnet_list}"
    subnet_list.each do |subnet|
      az = subnet[:availability_zone]
      az_subnet = best_subnet_per_az.fetch(az, nil)

      next if az_subnet.is_a?(Hash) && az_subnet[:available_ips] > subnet[:available_ips]

      Log.debug("Selecting subnet #{subnet[:id]} for AZ #{az} with #{subnet[:available_ips]} ips available")
      best_subnet_per_az[az] = subnet
    end

    Log.info "Selecting best subnets per az: #{best_subnet_per_az}"

    return best_subnet_per_az
  end
end
