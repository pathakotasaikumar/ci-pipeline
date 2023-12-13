# Helper class for tag related operations
class TagHelper
  # get_tag_values function is to get value of the tag passed as tag_key
  # if tag_key already present in tags then return the value present in tags else return deafult value passed
  def self.get_tag_values(tags: nil, default_value: nil, tag_key: nil)
    result_tags = []
    unless tags.nil?
      tags.each do |tag|
        if tag[:key] == tag_key
          result_tags.push({ key: tag[:key], value: tag[:value] })
        end
      end
    end
    result_tags.push({ key: tag_key, value: default_value }) if result_tags.empty?
    return result_tags
  end
end
