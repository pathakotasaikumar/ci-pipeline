module Pipeline
  class Feature
    def initialize(component_name, specification)
      @component_name = component_name
      @enabled = specification.fetch 'Enabled'
    end

    # Returns name of the action
    # @return [String] Name of the action
    def name
      # to be implemented in the inheriting class
    end

    def activate(stage)
      raise "Features #{name} may not be activated at #{stage} stage" unless valid_stages.include?(stage)
      # to be implemented in the inheriting class
    end

    def deactivate
      # to be implemented in the inheriting class
    end

    # Returns feature tags to be attached to the component on creation
    # @return [List] List of feature tags [{key: feature, value: status}]
    def feature_tags
      # to be implemented in the inheriting class
    end

    # @return [Hash] Return exposed feature properties
    def feature_properties
      # to be implemented in the inheriting class
    end

    # @return [Hash] Return exposed feature properties
    def valid_stages
      # to be implemented in the inheriting class
    end

    # @return [Bool] Whether feature is enabled or not
    def enabled?
      @enabled.to_s.downcase == 'true'
    end

    def self.instantiate(component_name, name, specification)
      raise ArgumentError, "Feature #{name} must be specified" if name.nil?

      feature_name = name.downcase
      case feature_name
      when "qualys"
        require 'pipeline/features/qualys'
        Pipeline::Features::Qualys.new(component_name, specification)
      when "customtags"
        require 'pipeline/features/customtags'
        Pipeline::Features::CustomTags.new(component_name, specification)
      when "datadog"
        require "pipeline/features/datadog"
        Pipeline::Features::Datadog.new(component_name, specification)
      when "codedeploy"
        require "pipeline/features/codedeploy"
        Pipeline::Features::CodeDeploy.new(component_name, specification)
      when "ips"
        require "pipeline/features/ips"
        Pipeline::Features::IPS.new(component_name, specification)
      when "longlived"
        require "pipeline/features/longlived"
        Pipeline::Features::Longlived.new(component_name, specification)
      else
        raise "Unknown feature #{name.inspect}"
      end
    end
  end
end
