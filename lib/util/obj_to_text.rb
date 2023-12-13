require 'json'

class ObjToText
  # Transform a key-value pair Hash to inifile formatted text
  def self.generate_flat_config(
    variables: nil,
    key_replace_regex: /[^a-zA-Z0-9_]/,
    quote_strings: false,
    line_prefix: "",
    line_ending: "\n",
    flat_hash_config: false
  )
    raise "Expecting a Hash, but received #{variables.class.inspect}" unless variables.is_a? Hash

    output = ""
    variables.each do |key, value|
      key = key.gsub(key_replace_regex, '_')

      if value.is_a? String
        value = value.inspect
      elsif value.is_a? Array
        value = value.join(',').inspect
      else
        if flat_hash_config && value.is_a?(Hash)
          # this block has been added to generate the flat string for the pipeline features.txt file
          new_key = "#{line_prefix}#{key}_"
          new_hash = value.inject({}) do |returned_hash, (key, value)|
            returned_hash["#{new_key}#{key}"] = value;
            returned_hash
          end
          variables.delete(key)
          output = generate_flat_config(
            variables: JsonTools.recursive_merge(variables, new_hash),
            key_replace_regex: key_replace_regex,
            quote_strings: quote_strings,
            line_prefix: line_prefix,
            line_ending: line_ending,
            flat_hash_config: flat_hash_config
          )
          return output
        else
          value = JSON.dump(value).inspect
        end
      end

      if quote_strings == false
        value = value[1..-2]
      elsif quote_strings == :special
        value = value[1..-2] unless value[1..-2] =~ / |\\|"|'/
      end
      output += "#{line_prefix}#{key}=#{value}#{line_ending}"
    end
    return output
  end

  # Renders array of arrays in a table-formatted way
  # @param data [Array[Array]] array of arrays to render
  # @return [Array] array of resulting strings
  def self.to_string_table(data)
    result = []

    column_sizes = data.reduce([]) do |lengths, row|
      row.each_with_index.map { |iterand, index| [lengths[index] || 0, iterand.to_s.length].max }
    end
    result << head = '-' * (column_sizes.inject(&:+) + (3 * column_sizes.count) + 1)

    data.each do |row|
      row = row.fill(nil, row.size..(column_sizes.size - 1))
      row = row.each_with_index.map { |v, i| v = v.to_s + ' ' * (column_sizes[i] - v.to_s.length) }
      result << '| ' + row.join(' | ') + ' |'
    end

    result << head

    result
  end
end
