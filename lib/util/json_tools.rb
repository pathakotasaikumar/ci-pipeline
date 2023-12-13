require 'json'

# Helper class for JSON-related operations
class JsonTools
  def self.parse(json)
    return JSON.parse(json)
  end

  def self.pretty_generate(object)
    return JSON.pretty_generate(object)
  end

  def self.contain_value?(item, value)
    return true if item.nil?
    if item.is_a? Hash
      return item.any? { |k, v| contain_value?(v, value) }
    elsif item.is_a? Array
      return item.any? { |v| contain_value?(v, value) }
    else
      return item == value
    end
  end

  def self.get(object, property_path, default = :undef)
    raise "Expecting Hash for parameter 'object', received #{object.class}" unless object.is_a? Hash

    # Split by '.' to get the key hierarchy
    keys = property_path.split('.')

    # Loop through the key hierarchy
    keys.each do |key|
      if object.is_a? Hash and object.has_key? key
        # Found the key at the current level - drill into it
        object = object[key]
      else
        # Key was not found (property path cannot be resolved) - bail out
        object = :undef
        break
      end
    end

    if object == :undef
      # Property path did not resolve to a value, return the default or raise an error if no default was supplied
      raise "Could not find property at path #{property_path.inspect}" if default == :undef

      return default
    else
      # Property path resolved to a value, return it
      return object
    end
  end

  def self.transfer(from_object, property_path, to_object, default = :undef)
    keys = property_path.split('.')
    path_keys = keys[0..-2]
    key = keys[-1]

    value = :undef

    # Create the path in the destination object
    path_keys.each do |path_key|
      if value == :undef
        if from_object.is_a? Hash and from_object.has_key? path_key
          from_object = from_object[path_key]
        else
          return if default == :undef
          raise "Could not find property at path #{property_path.inspect}" if default == :error

          value = default
        end
      end
      raise "Cannot set property in destination object - parent of key #{path_key.inspect} is a #{to_object.class}, but should be a Hash" unless to_object.is_a? Hash

      to_object[path_key] ||= {}
      to_object = to_object[path_key]
    end

    # Transfer the value from the source object to the destination object
    raise "Cannot set property in destination object - parent of key #{key.inspect} is type #{to_object.class}, but should be a Hash" unless to_object.is_a? Hash

    if value == :undef
      if from_object.is_a? Hash and from_object.has_key? key
        value = from_object[key]
      else
        raise "Could not find property at path #{property_path.inspect}" if default == :error

        value = default
      end
    end

    return if value == :undef

    to_object[key] = value
  end

  def self.hash_to_cfn_join(input)
    raise ArgumentError unless input.is_a? Hash

    join_array = []
    input.each do |key, value|
      # no implicit conversion of Hash into String>
      # we need to check if it is a String first!
      if key.is_a?(String) && /Ref|Fn::/.match(key)
        return { "Fn::Join" => ["", join_array.push("\"", { key => value }, "\"")] }
      elsif key.is_a? Hash
        join_array.push({ "Fn::Join" => ["", [self.hash_to_cfn_join(key), "\"#{value}\""]] })
      elsif value.is_a? Hash
        join_array.push({ "Fn::Join" => ["", ["\"#{key}\":", self.hash_to_cfn_join(value)]] })
      else
        join_array.push("\"#{key}\":\"#{value}\"")
      end
    end
    return { "Fn::Join" => [",", join_array] }
  end

  def self.get_from_hash(hash, key, default = :undef)
    # Lookup the key in the context
    return hash[key] if hash.has_key? key

    # Use the default value if one was provided
    return default if default != :undef

    # Could not find key in the context and a default value was not provided
    raise "Cannot find #{key.inspect} and a default value was not provided"
  end

  def self.set_in_hash(hash, key_value_hash, key_prefix = '')
    # Save all key-value pairs into the hash
    key_value_hash.each do |key, value|
      hash[key_prefix + key] = value
    end

    return hash
  end

  def self.delete_from_hash(hash, keys)
    # Delete all specified keys from the hash
    keys.each do |key|
      hash.delete(key)
    end
  end

  def self.first(name, items, default = :undef)
    items.each do |item|
      return item unless item.nil? or item.empty?
    end
    return default unless default == :undef

    raise "Could not determine #{name}"
  end

  def self.set_unless_nil(hash, key, value)
    hash[key] = value unless value.nil?
  end

  # Function to create a Hash value pair
  # sample return from the function is : { "ams01" => {"c031" => "value"}}
  # @param property_path [String]
  # @param object [object]
  def self.set(object, property_path)
    # Split by '.' to get the key hierarchy
    keys = property_path.split('.')

    # push the object to the array
    keys.push(object)

    return keys.reverse.inject { |mem, var| { var => mem } }
  end

  # Function to merge the Hash object recursively
  # @param merge_from [Hash] Physical snapshot id
  # @param merge_to [Hash] Target component name
  def self.recursive_merge(merge_from, merge_to)
    raise "Parameters must be an Hash" unless merge_from.is_a?(Hash) and merge_to.is_a?(Hash)

    merge_from.merge(merge_to) do |_, x, y|
      x.is_a?(Hash) && y.is_a?(Hash) ? recursive_merge(x, y) : [*x, *y]
    end
  end
end
