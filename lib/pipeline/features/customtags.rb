# Pipeline::Features::CustomTags permits developers to add thier own tags.
# for example: 'Domain: Mobile' which may assist with monitoring/billing.

require_relative '../feature'
module Pipeline
  module Features
    # Enable the customtags feature and create tags
    class CustomTags < Feature
      def initialize(component_name, specification)
        super
        @customtags = specification.fetch('Tags', nil)
      end

      # Return name the feature name as a string
      # @return [String] name
      def name
        'customtags'
      end

      # Returns component tags
      # @return [Hash] Component tags as key / values
      def _component_tags
        tags = {}
        Defaults.get_tags(@component_name).map do |tag|
          tags[tag[:key]] = tag[:value]
        end
        return tags
      end

      # @return (see Pipeline::Feature#feature_tags)
      def feature_tags
        feature_status = enabled? ? 'enabled' : 'disabled'
        tags = [
          {
            key: "feature_#{name}",
            value: feature_status
          }
        ]

        # here we iterate over @customtags instance variable to build out array
        @customtags.each do |tag_key, tag_value|
          if tag_key == 'ProjectCode'
            tags << { key: "#{tag_key}", value: tag_value }
          else
            tags << { key: "#{name}_#{tag_key}", value: tag_value }
          end
        end
        return tags
      end

      # @return (see Pipeline::Feature#feature_properties)
      def feature_properties
        { 'status' => enabled? ? 'enabled' : 'disabled' }
      end
    end
  end
end
