require 'context_class'

class ComponentContext
  def initialize(state_storage, sections)
    @state_storage = state_storage
    @sections = sections

    Log.debug "Creating new instance of ComponentContext"
    Log.debug " - storage provider: #{@state_storage.class}"
    Log.debug " - sections: #{@sections}"

    @mutex = Mutex.new

    @context = {}
    @context_modified = false

    if Defaults.is_cd_pipeline_task?
      Log.debug "Fetching Application Secret Manager SSM parameters under pipeline CD task: #{Defaults.pipeline_task}"
      _load_application_secret_parameters
    else
      Log.debug "Skipping Application Secret Manager SSM parameters under pipeline non-CD task: #{Defaults.pipeline_task}"
    end
  end

  def _load_application_secret_parameters
    begin
      # fail faster under unit tests, skipping timouts to create real clients
      # we don't use Context.environment.variable as it isn't available this time over Rake tasks initialization
      # would result in "uninitialized constant EnvironmentContext::Context" error
      raise 'Unable to obtain parameters under unit test workload' if ENV['local_pipeline_unit_testing'] == 'true'

      Log.info "Fetching Application Secret Manager SSM parameters, pipeline task: #{Defaults.pipeline_task}"

      qda = _qda_secret_parameter_path
      qda_common = _qda_common_secret_parameter_path
      legacy = _legacy_secret_parameter_path
      legacy_common = _legacy_common_secret_parameter_path
      as = _app_service_secret_parameter_path
      as_common = _app_service_common_secret_parameter_path

      ssm_parameter_prefix = [legacy, legacy_common, qda, qda_common, as, as_common]
      parameters_values = {}
      variables = {}
      ssm_parameter_prefix.each do |prefix|
        Log.debug "SSM path path used: #{prefix}"
        parameters = AwsHelper.ssm_get_parameters_by_path(
          path: prefix,
          recursive: false,
          with_decryption: true,
          assume_provision_client: true
        ).sort_by { |p| p.name }
        Log.debug "Fetched #{parameters.map.count} parameters under path #{prefix}"
        parameters.map do |parameter|
          parameters_values = parameters_values.merge(YAML.load(parameter.value))
        end
      end

      Log.info "Replacement of wildcard will take place in case you're using @wildcard-qcpaws in Code"
      Log.info "The WildCard certificate is: #{(AwsHelper.ssm_get_provision_parameter(name: '/qcp/acm_certificate_arn'))}"

      parameters_values.each do |key, value|
        Log.debug "Consumed Application secret parameter from SSM: #{key}"
        variables[key] = value
      end

      set_variables('app', variables)
    rescue => e
      Log.error "Unable to fetch Application secret parameters, build will continue but deployment might fail - #{e}"
    ensure
      Log.info  "Fetching Application secret parameters finished"
    end
  end

  def _legacy_secret_parameter_path
    sections = Defaults.sections
    [
      '/Application',
      sections[:ams],
      sections[:qda],
      sections[:as],
      sections[:ase]
    ].join('/')
  end

  def _legacy_common_secret_parameter_path
    sections = Defaults.sections
    [
      '/Application',
      sections[:ams],
      sections[:qda],
      sections[:as],
      '_common'
    ].join('/')
  end

  def _qda_secret_parameter_path
    sections = Defaults.sections
    [
      '/Application',
      sections[:qda],
      sections[:ase]
    ].join('/')
  end

  def _qda_common_secret_parameter_path
    sections = Defaults.sections
    [
      '/Application',
      sections[:qda],
      '_common'
    ].join('/')
  end

  def _app_service_secret_parameter_path
    sections = Defaults.sections
    [
      '/ApplicationService',
      sections[:qda],
      sections[:as],
      sections[:ase]
    ].join('/')
  end

  def _app_service_common_secret_parameter_path
    sections = Defaults.sections
    [
      '/ApplicationService',
      sections[:qda],
      sections[:as],
      '_common'
    ].join('/')
  end

  # Function to merge the Hash object recursively
  # @param merge_from [Hash] Physical snapshot id
  # @param merge_to [Hash] Target component name
  def recursive_merge(merge_from, merge_to)
    raise "Parameters must be an Hash" unless merge_from.is_a?(Hash) or merge_to.is_a?(Hash)

    merge_from.merge(merge_to) do |_, x, y|
      x.is_a?(Hash) && y.is_a?(Hash) ? recursive_merge(x, y) : [*x, *y]
    end
  end

  # function to load all the component related variable from the context
  # @param component_name [String]
  # @param build_number [String]
  def load_context(component_name: nil, build_number: nil)
    context = {}
    build_number ||= @sections[:build]
    _context(build: build_number).each do |key, value|
      if component_name.nil? or key.start_with? "#{component_name}."
        context[key] = Marshal.load(Marshal.dump(value))
      end
    end
    context
  end

  # function to set the all component variables into context
  # @param variables [String]
  def set_all(variables)
    @context_modified = true
    variables.each { |key, value| _context[key] = value }
  end

  # return the stack id for the component and build number
  # @param component_name [String]
  # @param build_number [Number]
  def stack_id(component_name, build_number = nil)
    build_number ||= @sections[:build]
    _context(build: build_number)["#{component_name}.StackId"]
  end

  # return the stack name for the component and build number
  # @param component_name [String]
  # @param build_number [Number]
  def stack_name(component_name, build_number = nil)
    build_number ||= @sections[:build]
    _context(build: build_number)["#{component_name}.StackName"]
  end

  # return the build number for the component and build number
  # @param component_name [String]
  # @param build_number [Number]
  def build_number(component_name, build_number = nil)
    build_number ||= @sections[:build]
    _context(build: build_number)["#{component_name}.BuildNumber"]
  end

  # function to add the variable into context
  # @param component_name [String]
  # @param variables [String]
  def set_variables(component_name, variables)
    @context_modified = true
    variables.each { |key, value| _context["#{component_name}.#{key}"] = value }
  end

  # function to delete the variable from the context
  # @param component_name [String]
  # @param prefix [String]
  def delete_variables(component_name, prefix)
    @context_modified = true
    _context.delete_if { |key, value| key.start_with? prefix }
  end

  # find the variable value from the context
  # @param component_name [String]
  # @param variable_name [String]
  # @param build_number [String]
  def variable(component_name, variable_name, default = :undef, build_number = nil)
    key = "#{component_name}.#{variable_name}"
    build_number ||= @sections[:build]
    return _context(build: build_number)[key] if _context(build: build_number).key? key
    return default unless default == :undef

    raise "Could not find variable #{variable_name} for component #{component_name}, and no default was supplied."
  end

  # Function to clone the context value
  # the arguments must be Hash value or can be empty
  # and the format of arguments variables(build: 3, ams: ams01)
  # @param context_sections [Hash]
  def variables(**context_sections)
    if context_sections[:component_name].nil?
      _context(**context_sections).clone
    else
      _context(**context_sections).select { |key, _| key.start_with? "#{context_sections[:component_name]}." }
    end
  end

  # function to set the security group id into the context
  # @param component_name [String]
  # @param stack_id [String]
  # @param security_item_map [Array]
  def set_security_details(component_name, stack_id, security_item_map)
    @context_modified = true
    security_item_map.each do |key, value|
      next if key.start_with? 'Stack'

      _context["#{component_name}.Security#{key}"] = value
    end

    _context["#{component_name}.SecurityStackId"] = stack_id
  end

  # return the security group id for the component and build number
  # @param component_name [String]
  # @param sg_name [String]
  # @param build_number [Number]
  def sg_id(component_name, sg_name, build_number = nil)
    build_number ||= @sections[:build]
    _context(build: build_number)["#{component_name}.Security#{sg_name}Id"]
  end

  # return the role ARN for the component and build number
  # @param component_name [String]
  # @param role_name [String]
  # @param build_number [Number]
  def role_arn(component_name, role_name, build_number = nil)
    build_number ||= @sections[:build]
    _context(build: build_number)["#{component_name}.Security#{role_name}Arn"]
  end

  # return the role name for the component and build number
  # @param component_name [String]
  # @param role_name [String]
  # @param build_number [Number]
  def role_name(component_name, role_name, build_number = nil)
    arn = role_arn(component_name, role_name, build_number)
    return nil if arn.nil?

    arn.split(':')[-1].sub(/^role\//, "")
  end

  # return the security stack id for the component and build number
  # @param component_name [String]
  # @param build_number [Number]
  def security_stack_id(component_name, build_number = nil)
    build_number ||= @sections[:build]
    _context(build: build_number)["#{component_name}.SecurityStackId"]
  end

  # function update the context value to s3
  def flush
    section_path = default_section_variable.values.join('.')
    context_value = JsonTools.get(@context, section_path, nil)
    return unless @context_modified && !context_value.nil?

    Log.info "Saving component context"
    @state_storage.save(_context_path, context_value)
    @context_modified = false
  end

  # Performs iterative replacement of strings matching context variables
  # User primarily for nested Hashes and Arrays
  # @param content [Object] Nested content to iterate over
  def replace_variables(content)
    require 'core/object/deep_replace'
    Object.include Core::Object::DeepReplace
    content.deep_replace do |value|
      found = value.match('@(?<component>[\w-]+)\.(?<variable>[\w-]+)')
      next value if found.nil?

      context_var = variable(found[:component], found[:variable], nil)
      if context_var.nil?
        Log.warn "Unable to locate context variable for '#{value}'"
        value
      else
        Log.debug "Replaced: #{value} -> #{context_var}"
        # Recurse through the string after replacement until there are no more variables
        replace_variables(value.sub("@#{found[:component]}.#{found[:variable]}", context_var))
      end
    end
  end

  # Performs iterative replacement of strings matching context variables
  # User primarily for nested Hashes and Arrays
  # @param content [Object] Nested content to iterate over
  def deep_find_variable(content:, pattern:)
    require 'core/object/deep_replace'
    Object.include Core::Object::DeepReplace
    content.deep_replace do |value|
      found = value.match(pattern)
      return true unless found.nil?

      next value
    end

    return false
  end

  # Function to dump the context variable
  # @param component_name [String] component name
  # @param context_skip_keys [Array] context keys to skip from dumping the variable
  # @param context_skip_to_encryption_regex [String]  Regex to skip from encryption of variable
  def dump_variables(component_name, context_skip_keys = [], context_skip_to_encryption_regex = nil)
    skip_keys = %w(Template _private_) + context_skip_keys

    context_variables = (variables || {}).inject({}) do |memo, (key, value)|
      next memo if skip_keys.any? { |skip_key| key.include? skip_key }

      # Skip to encrypt if the regex is matched - condition added to skip the app secrets(e.g app key is - app.DatabaseWord)
      if context_skip_to_encryption_regex.nil? || context_skip_to_encryption_regex.to_s.empty? || key.match(context_skip_to_encryption_regex).nil?
        # Encrypt the value if it is a password
        if value.is_a?(String) && key.downcase.include?("password")
          value = AwsHelper.kms_encrypt_data(Context.kms.secrets_key_arn, value)
        end
      end
      memo[key] = value
      memo
    end

    deployment_env = Defaults.sections[:env] == "prod" ? "Production" : "NonProduction"
    context_variables["pipeline.DeploymentEnv"] = deployment_env
    context_variables["pipeline.Component"] = component_name
    context_variables
  end

  private

  # Function to load the context value from the S3
  # the arguments must be Hash value or can be empty
  # and the format of arguments _context(build: 3, ams: ams01)
  # @param context_sections [Hash]
  def _context(**context_sections)
    keys_valid = context_sections.keys.all? do |s|
      [:ams, :qda, :as, :ase, :branch, :build, :component_name].include?(s)
    end

    raise ArgumentError "Error: Invalid arguments are passed #{context_sections}" unless keys_valid

    combined_sections = @sections.merge(context_sections)
    ams = combined_sections[:ams]
    qda = combined_sections[:qda]
    as  = combined_sections[:as]
    ase = combined_sections[:ase]
    branch = combined_sections[:branch]
    build = combined_sections[:build]
    context_path = "#{ams}.#{qda}.#{as}.#{ase}.#{branch}.#{build}"
    # Component context must support multi-threading, synchronize creation of the context hash
    @mutex.synchronize do
      copy_context = @context
      context_value = JsonTools.get(copy_context, context_path, {})
      if context_value.nil? || context_value.empty?
        Log.info "Loading component context #{context_path}"
        context_value = @state_storage.load(_context_path(combined_sections)) || {}
        latest_context = JsonTools.set(context_value, context_path)
        @context = recursive_merge(@context, latest_context)
      end
    end
    JsonTools.get(@context, context_path, {})
  end

  # Constructing the component path from the section variables
  # the arguments must be Hash value or can be empty
  # and the format of arguments _context_path(build: 3, ams: ams01)
  # @param sections [Hash]
  # @return (Array)
  def _context_path(sections = nil)
    sections ||= default_section_variable
    @context_path = [
      sections[:ams],
      sections[:qda],
      sections[:as],
      sections[:ase],
      sections[:branch],
      sections[:build],
      'Component'
    ]
  end

  # Default section variables method
  # @return (Hash)
  def default_section_variable
    {
      ams: @sections[:ams],
      qda: @sections[:qda],
      as: @sections[:as],
      ase: @sections[:ase],
      branch: @sections[:branch],
      build: @sections[:build]
    }
  end
end
