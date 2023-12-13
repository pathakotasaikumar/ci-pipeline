require 'util/object_space_utils'
require 'services/service_base'
require 'validation/validation_service'

include Qantas::Pipeline::Services

module Qantas
  module Pipeline
    module Validation
      ValidationInfo = Struct.new(
        :valid,
        :message,
        :component_info,
        :level,
        :validator_name
      ) do
        def initialize
          @valid = false
        end

        def to_s
          "#{_format_valid} - #{_format_level} - #{_format_component_name} - #{message} (#{validator_name})"
        end

        private

        def _format_component_name
          component_info.component_name
        end

        def _format_level
          level.to_s.upcase
        end

        def _format_valid
          if valid
            "[+]"
          else
            "[-]"
          end
        end
      end

      class ValidatorBase < ServiceBase
        def validate(data:)
          if !data.is_a?(ValidationData)
            raise "data should be of type ValidationData"
          end

          []
        end

        private

        def _get_components_by_type(component_infos:, type:)
          type_string = type.downcase
          component_infos.select { |c| c.component_hash.fetch('Type').downcase == type_string }
        end

        def _get_configurations_by_type(component_info:, type:)
          result = {}

          type_string = type.downcase
          configuration = component_info.component_hash.fetch('Configuration')

          configuration.each { |section_name, section_value|
            if section_value.fetch('Type').downcase == type_string
              result[section_name] = section_value
            end
          }

          result
        end

        def _create_result(component_info:)
          result = ValidationInfo.new

          result.valid = false
          result.validator_name = name
          result.component_info = component_info

          result
        end

        def _create_error(component_info:)
          result = _create_result(component_info: component_info)

          result.level = :error
          result.valid = false

          result
        end

        def _create_info(component_info:)
          result = _create_result(component_info: component_info)

          result.level = :info
          result.valid = true

          result
        end
      end
    end
  end
end
