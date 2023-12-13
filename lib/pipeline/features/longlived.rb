require_relative '../feature'

module Pipeline
  module Features
    class Longlived < Feature
      def initialize(component_name, specification)
        @puppet_server = specification.fetch('PuppetServer', nil)
        @puppet_environment = specification.fetch('PuppetEnvironment', nil)
        @puppet_development = specification.fetch('PuppetDevelopment', false)
        @patch_group = specification.fetch('PatchGroup', nil)
        @restore_ami = specification.fetch('RestoreAMI', nil)
        super
      end

      def name
        'longlived'
      end

      # activate feature
      def activate
        # reserved for future functionality
      end

      # deactivate feature
      def deactivate
        # Reserved for future functionality
      end

      # @return [String] Value for the puppet_server from the feature block or the defaults value
      def puppet_server
        return @puppet_server unless @puppet_server.nil?

        return Defaults.puppet_server
      end

      # @return [String] Value for the puppet environment from the feature block or the defaults value
      def puppet_environment
        return @puppet_environment unless @puppet_environment.nil?

        # Return default puppet for the environment
        if Defaults.sections[:env] == 'nonp'
          Defaults.puppet_qcp_lri_nonproduction
        else
          Defaults.puppet_qcp_lri_production
        end
      end

      # @return [Booolean] Value for the puppet_development from the feature block or the default value
      def puppet_development
        @puppet_development
      end

      def restore_ami
        @restore_ami
      end

      # @return (see Pipeline::Feature#feature_tags)
      def feature_tags
        feature_status = enabled? ? 'enabled' : 'disabled'

        tags = [{ key: "feature_#{name}", value: feature_status }]
        tags << { key: "Patch Group", value: patch_group } if enabled?
        return tags
      end

      # @return (see Pipeline::Feature#feature_properties)
      def feature_properties
        feature_properties = { 'status' => enabled? ? 'enabled' : 'disabled' }

        if enabled?
          feature_properties['PuppetServer'] = puppet_server
          feature_properties['PuppetEnvironment'] = puppet_environment
          feature_properties['PuppetDevelopment'] = puppet_development
          feature_properties['PatchGroup'] = patch_group
          feature_properties['RestoreAMI'] = restore_ami
        end

        return feature_properties
      end

      # @return [string] Value for the patch_group from the feature block or select a sane
      # value based on the OS type of the instance.
      def patch_group
        return @patch_group unless @patch_group.blank?

        ostype = Context.component.variable(@component_name, 'operating_system')
        case ostype
        when /centos/
          Defaults.centos_patchgroup
        when /rhel/
          Defaults.rhel_patchgroup
        when /windows/
          Defaults.windows_patchgroup
        else
          raise "Unable to determine Patch Group for operating system: #{ostype}"
        end
      end
    end
  end
end
