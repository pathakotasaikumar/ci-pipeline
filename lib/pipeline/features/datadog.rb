require_relative '../feature'

module Pipeline
  module Features
    class Datadog < Feature
      def initialize(component_name, specification)
        super
      end

      def name
        'datadog'
      end

      # activate feature
      def activate
        # reserved for future functionality
      end

      # deactivate feature
      def deactivate
        # reserved for future functionality
      end

      # @return (see Pipeline::Feature#feature_tags)
      def feature_tags
        feature_status = enabled? ? 'enabled' : 'disabled'
        [
          {
            key: "feature_#{name}",
            value: feature_status
          }
        ]
      end

      # @return (see Pipeline::Feature#feature_properties)
      def feature_properties
        feature_properties = { 'status' => enabled? ? 'enabled' : 'disabled' }
        feature_properties['apikey'] = _api_key if enabled?

        return feature_properties
      end

      private

      # @return [String] Retrieve AMS/Environment specific api key
      def _api_key
        sections = Defaults.sections
        ams_key = "#{sections[:ams]}-#{sections[:env]}"
        datadog_keys = Defaults.datadog_api_keys

        raise "Unable to find Datadog API keys" if datadog_keys.blank?

        api_key = JSON.parse(datadog_keys)[ams_key.downcase]
        return api_key
      end
    end
  end
end
