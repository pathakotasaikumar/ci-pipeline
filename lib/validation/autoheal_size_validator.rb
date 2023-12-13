require "#{BASE_DIR}/lib/validation/validator_base"

include Qantas::Pipeline::Validation

module Qantas
  module Pipeline
    module Validation
      class AutohealSizeValidator < ValidatorBase
        @allowed_values;

        def initialize
          @allowed_values = [0, 1]
        end

        def name
          "autoheal-autoscale-sizes-validation"
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

          Log.debug "Fetching aws/autoheal components..."
          autoheal_component_infos = _get_components_by_type(
            component_infos: component_infos,
            type: 'aws/autoheal'
          )

          if autoheal_component_infos.count > 0
            Log.info "Validating [#{autoheal_component_infos.count}] aws/autoheal components..."
            autoheal_component_infos.each do |autoheal_component_info|
              _validate_component(autoheal_component_info, result)
            end
          else
            Log.debug "No aws/autoheal components found, skipping validation..."
          end
        end

        def _validate_component(component_info, result)
          Log.debug "Fetching AutoScalingGroup for aws/autoheal component"
          autoscaling_groups = _get_configurations_by_type(
            component_info: component_info,
            type: "AWS::AutoScaling::AutoScalingGroup"
          )

          Log.debug "Validating AutoScalingGroups for aws/autoheal component"
          autoscaling_groups.each { |autoscaling_group_namem, autoscaling_group|
            properties = autoscaling_group.fetch('Properties')

            min_size         = properties.fetch('MinSize', nil)
            max_size         = properties.fetch('MaxSize', nil)
            desired_capacity = properties.fetch('DesiredCapacity', nil)

            _validate_size(min_size, component_info, result, "aws/autoheal component only supports '0' and '1' for MinSize property")
            _validate_size(max_size, component_info, result, "aws/autoheal component only supports '0' and '1' for MaxSize property")
            _validate_size(desired_capacity, component_info, result, "aws/autoheal component only supports '0' and '1' for DesiredCapacity property")
          }
        end

        def _allowed_values
          @allowed_values
        end

        def _validate_size(value, component_info, result, message)
          # Failed to load all components -
          # aws/autoheal component only supports '0' and '1' for MinSize, MaxSize and DesiredCapacity properties

          # https://jira.qantas.com.au/browse/QCPFB-114
          # https://bamboocd.qcpaws.qantas.com.au/browse/AMS02-A243S55DEV8-DEPLOY-1                    #

          if !value.nil? && !_allowed_values.include?(value.to_i)
            validation_result = _create_error(component_info: component_info)
          else
            validation_result = _create_info(component_info: component_info)
          end

          validation_result.message = message + " - value was: #{value}, allowed values: #{_allowed_values}"

          result << validation_result
        end
      end
    end
  end
end
