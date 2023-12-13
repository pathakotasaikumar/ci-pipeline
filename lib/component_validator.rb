require 'yaml'
require 'json'

# Validates component definitions producing errors/warnings on incorrect entries
class ComponentValidator
  def initialize(cloudformation_spec_dir, component_spec_dir)
    @cfn_spec = {}
    @component_spec_dir = component_spec_dir
    @validation_errors = []
    @validation_warnings = []

    @last_validation_errors = []
    @last_validation_warnings = []

    # Load CloudFormation resource specification
    Dir["#{cloudformation_spec_dir}/*"].each do |file|
      next unless [".yaml", ".json"].include? File.extname(file).downcase

      spec = _load_spec_file(file)
      @cfn_spec = _deep_merge(@cfn_spec, spec)
    end
  end

  # Returns an array of validation errors
  # @return [Array]
  def errors
    @validation_errors
  end

  # Returns an array of validation warnings
  # @return [Array]
  def warnings
    @validation_warnings
  end

  # Returns an array of the last validation errors cleared by .reset() call
  # @return [Array]
  def last_errors
    @last_validation_errors
  end

  # Returns an array of the last validation warnings cleared by .reset() call
  # @return [Array]
  def last_warnings
    @last_validation_warnings
  end

  # Cleans validation results exposes via errors/warnings
  # Old result is still available via last_errors/last_errors methods
  def reset
    @last_validation_errors = @validation_errors.clone
    @last_validation_warnings = @validation_warnings.clone

    @validation_errors = []
    @validation_warnings = []
  end

  def _save_error(message)
    @validation_errors << message
  end

  def _save_warning(message)
    @validation_warnings << message
  end

  # Validates component definition
  def validate(component_name, component_definition)
    component_definition = component_definition

    # Validate top-level component definition properties - exit if anything is wrong
    _validate_top_level_properties(component_name, component_definition)
    return unless errors.empty? and warnings.empty?

    # Load component specification
    resources = component_definition["Configuration"]
    component_type = component_definition["Type"]
    component_spec = _load_component_spec(component_type)

    # Sort resources into spec sections
    spec_resource_map = {}
    resources.each do |name, definition|
      section = _get_resource_spec(component_spec, name, definition)
      if section.nil?
        _save_error "Invalid resource #{name.inspect} found in definition"
      else
        spec_resource_map[section] ||= {}
        spec_resource_map[section][name] = definition
      end
    end

    # Validate definition
    _validate_resource_cardinality(component_spec, spec_resource_map)
    _validate_resource_properties(@cfn_spec, component_spec, spec_resource_map)
  end

  # Validate top-level component definition properties
  def _validate_top_level_properties(name, definition)
    component_name_regex = '^[a-zA-Z0-9\-_]+$'
    if !name.match(component_name_regex)
      _save_error "Bad component name #{name.inspect} - must match regex #{component_name_regex}"
    end

    if definition["Type"].is_a? String
      _save_warning "Component type #{definition["Type"].inspect} does not currenly have a validation spec - skipping validation" unless _spec_exists(definition["Type"])
    else
      _save_error "Property 'Type' must be a String in component definition"
    end

    _save_error "Property 'Configuration' must be a Hash in component definition" unless definition["Configuration"].is_a? Hash

    valid_top_level_properties = [
      "Actions",
      "AsirSet",
      "Branches",
      "Configuration",
      "Environments",
      "IngressPoint",
      "Persist",
      "Stage",
      "Type",
    ]
    invalid_properties = definition.keys - valid_top_level_properties
    invalid_properties.each do |invalid_property|
      _save_error "Invalid top-level property #{invalid_property.inspect}"
    end
  end

  # Validate the cardinality of resources
  def _validate_resource_cardinality(component_spec, spec_resource_map)
    component_spec.each do |spec_section, resource_spec|
      min, max = _parse_cardinality(resource_spec["Cardinality"])
      num_resources = (spec_resource_map[spec_section] || {}).length
      if num_resources > max or num_resources < min
        _save_error "Found #{num_resources} #{spec_section} resources - minimum is #{min} and maximum is #{max}"
      end
    end
  end

  # Validate properties in each resource
  def _validate_resource_properties(cfn_spec, component_spec, spec_resource_map)
    spec_resource_map.each do |spec_section, resources|
      spec_file = _create_spec(cfn_spec, component_spec[spec_section]["Specification"])

      resources.each do |resource_name, resource|
        _validate_properties(spec_file, resource_name, spec_file["ResourceTypes"][resource["Type"]], resource)
      end
    end
  end

  def _spec_exists(component_type)
    return File.file? "#{@component_spec_dir}/#{component_type}.yaml"
  end

  def _load_spec_file(filename)
    filetype = File.extname(filename).downcase
    if filetype == ".yaml"
      spec = YAML.load(File.read(filename))
    elsif filetype == ".json"
      spec = JSON.load(File.read(filename))
    else
      raise "Unknown file type for spec file #{filename.inspect}"
    end

    _make_types_canonical(spec["ResourceTypes"], spec["PropertyTypes"]) if spec.has_key? "ResourceTypes"
    _make_types_canonical(spec["PropertyTypes"], spec["PropertyTypes"]) if spec.has_key? "PropertyTypes"

    return spec
  end

  def _get_resource_spec(component_spec, resource_name, resource)
    component_spec.each do |spec_section, spec_definition|
      return spec_section if _resource_matches(spec_definition, resource_name, resource)
    end

    return nil
  end

  def _deep_merge(hash1, hash2)
    merger = proc { |key, v1, v2| Hash === v1 && Hash === v2 ? v1.merge(v2, &merger) : v2 }
    return hash1.merge(hash2, &merger)
  end

  def _load_component_spec(component_type)
    return _load_spec_file("#{@component_spec_dir}/#{component_type}.yaml")
  end

  def _make_types_canonical(spec, property_types)
    spec.each do |type, type_spec|
      next unless type_spec.has_key? "Properties"

      type = type.split('.')[0]

      type_spec["Properties"].each do |property, property_spec|
        next unless property_spec.has_key? "Type"

        if property_spec["Type"] == "List"
          next unless property_spec.has_key? "ItemType"
          # Skip if type is already a valid property type
          next if property_types.has_key? property_spec["ItemType"]
          # Skip if type is already canonical
          next if property_spec["ItemType"].include? "."

          # Canonicalise the item type
          property_spec["ItemType"] = "#{type}.#{property_spec["ItemType"]}"
        elsif property_spec["Type"] == "Map"
          next
        elsif property_spec["Type"] == "Enum"
          next
        else
          # Skip if type is already a valid property type
          next if property_types.has_key? property_spec["Type"]
          # Skip if type is already canonical
          next if property_spec["Type"].include? "."

          # Canonicalise the type
          property_spec["Type"] = "#{type}.#{property_spec["Type"]}"
        end
      end
    end
    return spec
  end

  def _resource_matches(spec, resource_name, resource)
    # Match based on resource name regex
    if spec.has_key? "Match"
      return false unless resource_name.match("^(#{spec["Match"]})$")
    end

    # Match based on resource type
    if spec.has_key? "Type"
      return false unless resource["Type"] == spec["Type"]
    end

    # Previous conditions all match
    return true
  end

  def _parse_cardinality(cardinality)
    matches = cardinality.to_s.match /^([0-9]+)(?:-([0-9]+))?$/
    raise "Invalid cardinality #{cardinality.inspect}" if matches.nil?

    min = matches[1].to_i
    max = (matches[2] || min).to_i

    return min, max
  end

  def _create_spec(cfn_spec, resource_spec)
    # Select only relevant resource types
    cfn_resource_types = cfn_spec["ResourceTypes"].select do |key, value|
      resource_spec["ResourceTypes"].has_key? key
    end

    # Select only relevant property types
    cfn_property_types = cfn_spec["PropertyTypes"].select do |key, value|
      next true if key.start_with? "Common" or key == "Tag"
      next true if resource_spec["ResourceTypes"].keys.any? { |resource_name| key.start_with? resource_name }

      next false
    end

    # Merge CloudFormation spec with component spec
    cfn_resource_types = _deep_merge(cfn_resource_types, resource_spec["ResourceTypes"] || {})
    cfn_property_types = _deep_merge(cfn_property_types, resource_spec["PropertyTypes"] || {})

    spec = {
      "ResourceTypes" => _make_types_canonical(cfn_resource_types, cfn_property_types),
      "PropertyTypes" => _make_types_canonical(cfn_property_types, cfn_property_types),
    }

    return spec
  end

  def eval_condition(condition, resource, type_spec)
    return false if condition.nil? or resource.nil?
    return false unless resource.is_a? Hash
    return false if condition == false
    return true if condition == true

    if condition.is_a? Hash
      raise "Bad spec condition #{condition.inspect} - multiple keys have been specified" unless condition.length == 1

      condition_key = condition.keys[0]
      condition_value = condition.values[0]

      if condition_key == "IfAny"
        # puts "Checking #{condition_key} of #{condition_value.inspect}"
        return condition_value.ensure_array.any? { |subcondition| eval_condition(subcondition, resource, type_spec) }
      elsif condition_key == "IfAll" or condition_key == "If"
        # puts "Checking #{condition_key} of #{condition_value.inspect}"
        return condition_value.ensure_array.all? { |subcondition| eval_condition(subcondition, resource, type_spec) }
      elsif condition_key == "UnlessAny" or condition_key == "Unless"
        # puts "Checking #{condition_key} of #{condition_value.inspect}"
        return !condition_value.ensure_array.any? { |subcondition| eval_condition(subcondition, resource, type_spec) }
      elsif condition_key == "UnlessAll"
        # puts "Checking #{condition_key} of #{condition_value.inspect}"
        return !condition_value.ensure_array.all? { |subcondition| eval_condition(subcondition, resource, type_spec) }
      else
        # puts "Checking property #{condition_key} = #{condition_value.inspect}"
        if resource.has_key? condition_key
          return resource[condition_key] == condition_value
        else
          return (type_spec[condition_key] || {})["Default"] == condition_value
        end
      end
    elsif condition.is_a? String
      # puts "Checking if property #{condition.inspect} exists"
      return resource.has_key? condition
    else
      raise "Bad spec condition #{condition.inspect} - expecting Hash or String, but received #{condition.class.inspect}"
    end
  end

  def is_required(key, type_spec, resource)
    return false if type_spec[key].nil?

    return eval_condition(type_spec[key]["Required"], resource, type_spec)
  end

  def is_configurable(key, type_spec, resource, default: false)
    return false if type_spec[key].nil?

    return default if !type_spec[key].is_a?(Hash)

    return eval_condition(type_spec[key].fetch("Configurable", default), resource, type_spec)
  end

  def _validate_properties(spec_file, name, type_spec, resource)
    resource = resource || {}
    resource.each do |key, value|
      fq_property_name = "#{name}.#{key}"

      # Handle special top-level keys
      if !name.include? '.'
        # Skip the Type key
        next if key == "Type"

        # Handle the special case of the "Properties" key
        if key == "Properties"
          _validate_properties(spec_file, fq_property_name, type_spec["Properties"], value)
          next
        end
      end

      if !(type_spec.has_key? key)
        _save_error "Unknown property #{fq_property_name.inspect} was set"
      elsif !is_configurable(key, type_spec, resource, default: true)
        _save_error "Non-configurable property #{fq_property_name.inspect} was set (Condition: #{(type_spec[key]['Configurable'] || 'none').inspect})"
      else
        _validate_property(spec_file, fq_property_name, type_spec[key], value)
      end
    end

    # Validate all required properties are set
    type_spec.each do |key, value|
      fq_property_name = "#{name}.#{key}"

      configurable = is_configurable(key, type_spec, resource, default: false)
      required = is_required(key, type_spec, resource)

      if configurable and required and !value.has_key? "Default" and !(resource.has_key? key)
        _save_error "Required property #{fq_property_name.inspect} has not been set (Condition: #{(type_spec[key]['Required'] || 'none').inspect})"
      end
    end
  end

  def _validate_property(spec_file, name, type_spec, value)
    if type_spec.has_key? "Type"
      type = type_spec["Type"]
      if type.include? "."
        # Property is a defined type - validate it
        subtype_spec = spec_file["ResourceTypes"][type] || (spec_file["PropertyTypes"][type] || {})["Properties"]
        if subtype_spec.nil?
          _save_error "Invalid type #{type.inspect} in spec - cannot validate"
        elsif !type_spec["TypeOverride"].nil?
          return true
        else
          _validate_properties(spec_file, name, subtype_spec, value)
        end
      else
        case type.downcase
        when "list"
          if value.is_a? Array
            _validate_list_items(spec_file, name, type_spec, value)
          elsif type_spec["AllowSingular"] == true
            _validate_list_items(spec_file, name, type_spec, [value])
          elsif value.is_a? String and value.start_with? "@"
            # Anchor - assume it resolves to a list and do nothing
          else
            _save_error "Bad type for property #{name.inspect} - expecting List"
          end
        when "map"
          return true if value.is_a? Hash

          _save_error "Bad type for property #{name.inspect} - expecting Map"
        when "json"
          return true
        when "enum"
          valid_values = type_spec["EnumValues"].ensure_array.map { |v| v.to_s }
          return true if valid_values.include? value.to_s

          _save_error "Bad value for property #{name.inspect} - must be one of: #{valid_values.join(', ')}"
        else
          _save_warning "#{name} is unhandled type #{type} - Skipping validation"
        end
      end
    else
      _validate_primitive_type(name, type_spec, value)
    end
  end

  def _get_type_spec(spec_file, type)
    return spec_file["ResourceTypes"][type] || (spec_file["PropertyTypes"][type] || {})["Properties"]
  end

  def _validate_list_items(spec_file, name, type_spec, list)
    for i in 0...list.length
      fq_property_name = "#{name}[#{i}]"
      if type_spec.has_key? "ItemType"
        # Item type is its own subtype
        subtype_spec = _get_type_spec(spec_file, type_spec["ItemType"])
        if subtype_spec.nil?
          _save_error "Invalid type #{type_spec["ItemType"].inspect} for property #{fq_property_name} - invalid spec, cannot validate"
        else
          _validate_properties(spec_file, fq_property_name, subtype_spec, list[i])
        end
      elsif type_spec.has_key? "PrimitiveItemType"
        # Item types are primitive
        _validate_primitive_type(fq_property_name, type_spec, list[i])
      else
        # Cannot determine type of items
        _save_warning "#{fq_property_name} was not validated - could not determine type of array items to validate against"
      end
    end
  end

  def _is_function(value)
    return false unless value.is_a? Hash
    return false unless value.length == 1
    return false unless value.keys[0] == "Ref" or value.keys[0].start_with? "Fn::"

    return true
  end

  def _validate_primitive_type(property_name, property_spec, value)
    primitive_type = property_spec["PrimitiveType"] || property_spec["PrimitiveItemType"]
    if primitive_type.nil?
      _save_warning "Skipping validation of property #{property_name.inspect} - not a primitive type"
      return true
    end

    case primitive_type.downcase
    when "string"
      return true if _is_function(value)

      if value.is_a? String
        if property_spec.has_key? "Regex" and !value.match(property_spec["Regex"])
          _save_error "Bad value for property #{property_name.inspect} - must match regex #{property_spec["Regex"]}"
        else
          return true
        end
      end
    when "json"
      return true
    when "map"
      return true if value.is_a? Hash
    when "integer", "long"
      return true if (Integer(value) rescue value).is_a? Integer

      _save_error "Bad type for property #{property_name.inspect} - expecting #{primitive_type}"
    when "double"
      return true if (Float(value) rescue value).is_a? Float

      _save_error "Bad type for property #{property_name.inspect} - expecting #{primitive_type}"
    when "boolean"
      return true if value.to_s == "true" or value.to_s == "false"

      _save_error "Bad type for property #{property_name.inspect} - expecting #{primitive_type}"
    else
      _save_warning "Skipping validation of property #{property_name.inspect} - unhandled property type #{primitive_type}"
    end

    return false
  end
end
