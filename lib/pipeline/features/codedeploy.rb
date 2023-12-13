require_relative '../feature'

module Pipeline
  module Features
    class CodeDeploy < Feature
      def initialize(component_name, specification)
        super
      end

      def name
        'codedeploy'
      end

      # activate feature
      def activate
      end

      # deactivate feature
      def deactivate
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
        { 'status' => enabled? ? 'enabled' : 'disabled' }
      end
    end
  end
end
