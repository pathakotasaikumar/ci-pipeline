require 'util/object_space_utils'
require 'validation/validator_base'
require 'services/service_base'

def _include_folder_services(folders, is_debug = false)
  folders.each do |folder|
    # include all 'common' halpers
    path = "#{folder}/**/*.rb"
    # puts "  - looking for files: #{path}"

    Dir.glob(path).each { |file|
      # puts "  - including service file: #{file}"
      require file
    }
  end
end

_include_folder_services ["#{BASE_DIR}/lib/validation"]

include Qantas::Pipeline::Services

module Qantas
  module Pipeline
    module Validation
      ValidationComponentInfo = Struct.new(
        :component_file,
        :component_name,
        :component_hash
      )

      class ValidationData
        attr_reader :app_containers

        def initialize
          @app_containers = {}
        end

        def add_component_info(
          app_container_info:,
          component_file:,
          component_name:,
          component_hash:
        )
          if !app_container_info.is_a?(AppContainerInfo)
            raise "app_container_info should be of type: #{AppContainerInfo.class}"
          end

          if app_container_info.nil?
            raise "app_container_info should not be nil"
          end

          component_infos = @app_containers.fetch(app_container_info, nil)

          if component_infos.nil?
            component_infos = []
            @app_containers[app_container_info] = component_infos
          end

          begin
            component_info = ValidationComponentInfo.new

            component_info.component_file = component_file
            component_info.component_name = component_name
            component_info.component_hash = component_hash

            component_infos << component_info
          rescue => e
            Log.warn "add_component_info error"
            Log.error e
          end
        end
      end

      ValidationResult = Struct.new(
        :valid,
        :results
      ) do
        def initialize
          super

          self.valid = false
          self.results ||= []
        end
      end

      class ValidationService < ServiceBase
        @validators;

        def validate(data:)
          if !data.is_a?(ValidationData)
            raise "data should be of type ValidationData"
          end

          result = ValidationResult.new
          result.results = []

          _validate(data, _validators, result)

          return result
        end

        private

        def _validate(data, validators, validation_result)
          valid = true

          validators.each { |validator_class_name, validator|
            Log.info "Running validator: #{validator.name} (#{validator_class_name})"
            validator_result = validator.validate(data: data)

            _check_validator_result validator_result

            validator_result.each do |result_info|
              if !result_info.valid
                valid = false
              end

              validation_result.results << result_info
            end
          }

          validation_result.valid = valid
        end

        def _check_validator_result(result)
          if !result.is_a?(Array)
            raise "validator result should be of type Array"
          end

          result.each do |result_info|
            if !result_info.is_a?(ValidationInfo)
              raise "every in validation result should be of type ValidationInfo"
            end
          end
        end

        def _validators
          _load_validators
          @validators
        end

        def _load_validators
          if @validators.nil?
            @validators = {}

            impl_classes = _load_classes(parent_class: Qantas::Pipeline::Validation::ValidatorBase)

            impl_classes.each do |impl_class|
              if impl_class == Qantas::Pipeline::Validation::ValidatorBase
                next
              end

              Log.debug "creating validator: #{impl_class}"

              impl_instance = impl_class.new
              @validators[impl_class] = impl_instance
            end
          end
        end

        def _load_classes(parent_class:)
          ObjectSpaceUtils.load_pipeline_classes(parent_class: parent_class)
        end
      end
    end
  end
end
