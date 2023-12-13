require 'base64'
require 'json'

# Generate a CloudFormation userdata tag containing lines of the specified file.
# Variables can be substituted by inserting the key between <| and |> tags in the userdata file. Substitution is done as
# a new element, so the substituted value can be runtime-resolved CloudFormation references.
# For example, add variable 'Region' to be a CloudFormation ref snippet:
# variables = {
#   'Region' => { 'Ref' => 'AWS::Region' }
# }
# UserData.load_aws_userdata("my_userdata.sh", variables)
#
# Then in the user data, we can reference this variable:
# REGION="<| Region |>"
#
# With the result being that the user will contain joined "REGION=\"",{ "Ref": "AWS::Region" },"\"\n"
#
class UserData
  # Regex to look for <| and |> tags in the text
  @@SPLIT_JSON_REGEX = /(.*?)(?:<\|(.*?)\|>)(.*\n)/

  def self._process_text(text, variables)
    join_array = []

    matches = text.match(@@SPLIT_JSON_REGEX)
    if matches.nil?
      # No tags in this text - add it as-is
      join_array.push(text)
    else
      if matches[1] != ""
        # All text before the tag
        join_array.push(matches[1])
      end

      if matches[2] != ""
        # The tag itself - perform variable substitution
        tag_text = matches[2].strip
        raise "Could not find substitution for variable #{tag_text.inspect}" unless variables.has_key? tag_text

        join_array.push(variables[tag_text])
      end

      # Recursively process all text after the tag, in case there are more tags
      join_array.concat(_process_text(matches[3], variables))
    end

    return join_array
  end

  def self.process_file(file_path, variables = {})
    file_lines = File.readlines(file_path)
    return "" if file_lines.nil?

    join_array = []
    file_lines.each { |line|
      join_array.concat(_process_text(line, variables))
    }

    return join_array.join
  end

  def self.load_aws_userdata(file_path, variables = {})
    Log.debug "Generating AWS userdata for file #{file_path}"

    raise ArgumentError, "Failed to load file '#{file_path}'" unless File.file?(file_path)

    file_lines = File.readlines(file_path)
    return "" if file_lines.nil?

    join_array = []
    file_lines.each { |line|
      join_array.concat(_process_text(line, variables))
    }

    # return the join_array encased by Fn::Base64 and joined by an empty string
    return { "Fn::Base64" => { "Fn::Join" => ["", join_array] } }
  end
end
