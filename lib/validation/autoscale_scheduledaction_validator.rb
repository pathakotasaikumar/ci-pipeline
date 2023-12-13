require "#{BASE_DIR}/lib/validation/validator_base"

include Qantas::Pipeline::Validation

module Qantas
  module Pipeline
    module Validation
      class AutoscaleSheduledActionValidator < ValidatorBase
        def initialize
        end

        def name
          "autoscale-sheduled-action-validation"
        end

        def validate(data:)
          # always call super to perform basic validation tasks
          result = super

          data.app_containers.each { |app_container_info, component_infos|
            _validate_app_container(data, app_container_info, component_infos, result)
          }

          return result
        end

        private

        def _validate_app_container(data, app_container_info, component_infos, result)
          Log.debug "Validating app container: #{app_container_info}"

          Log.debug "Fetching aws/autoscale components..."
          target_component_infos = _get_components_by_type(
            component_infos: component_infos,
            type: 'aws/autoscale'
          )

          if target_component_infos.count > 0
            Log.info "Validating [#{target_component_infos.count}] aws/autoscale components..."
            target_component_infos.each do |target_component_info|
              _validate_component(target_component_info, result)
            end
          else
            Log.debug "No aws/autoscale components found, skipping validation..."
          end
        end

        def _validate_component(component_info, result)
          Log.debug "Fetching AWS::AutoScaling::ScheduledAction for aws/autoscale component"
          scheduled_actions = _get_configurations_by_type(
            component_info: component_info,
            type: "AWS::AutoScaling::ScheduledAction"
          )

          Log.debug "Validating AutoScalingGroups for aws/autoheal component"
          scheduled_actions.each { |action_name, action|
            properties = action.fetch('Properties', {})

            min_size  = properties.fetch('MinSize', nil)
            max_size  = properties.fetch('MaxSize', nil)

            _validate_size_properties(
              min_size,
              max_size,
              component_info,
              result,
              "AWS::AutoScaling::ScheduledAction should have MinSize < MazSize"
            )
          }
        end

        def _validate_size_properties(min_size, max_size, component_info, result, message)
          # Enhance pipeline CI validation - check Min/Max values in AWS::AutoScaling::ScheduledAction
          # https://jira.qantas.com.au/browse/QCPFB-91

          validation_result = _create_info(component_info: component_info)

          if !min_size.nil? && !max_size.nil?
            if min_size > max_size
              validation_result = _create_error(component_info: component_info)
            end
          end

          validation_result.message = message + " - values were: MinSize: #{min_size} MaxSize: #{max_size}"

          result << validation_result
        end
      end
    end
  end
end
