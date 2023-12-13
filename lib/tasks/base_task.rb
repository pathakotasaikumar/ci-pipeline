require 'component'
require 'runner'

require "#{BASE_DIR}/lib/services/error_info_service.rb"
require "#{BASE_DIR}/lib/errors/pipeline_aggregate_error"

include Qantas::Pipeline::Errors

class BaseTask
  @_error_info_service = nil

  def name
    "base_task"
  end

  def initialize
  end

  def get_error_report(e)
    _error_info_service.to_pretty_print(e)
  end

  private

  # Returns an instance of PipelineAggregateError for giving message and extented_failed_state
  # Used with output of Runner.deploy(), release() or teardown() methods
  # @return [PipelineAggregateError]
  def _get_aggregate_failed_component_error(message, extented_failed_state)
    # it might be nil
    # Runner.deploy(), release() or teardown() might fails early wihtout any component refs
    if extented_failed_state.nil?
      extented_failed_state = []
    end

    raise PipelineAggregateError.new(
      message,
      extented_failed_state.map { |item|
        # wrap incoming component's error into the pipeline one
        pipeline_error = PipelineError.wrapError(item[:exception])

        # it might come from the error already, we'll override if not set
        if pipeline_error.component_name.to_s.empty?
          pipeline_error.component_name = item[:component_name]
        end

        pipeline_error
      }
    )
  end

  def _env
    ENV
  end

  # Checks if user defined actions need to be deployed
  # @return [Boolean]
  def _error_info_service
    if @_error_info_service.nil?
      @_error_info_service = ServiceContainer.instance.get_service(ErrorInfoService)
    end

    @_error_info_service
  end
end
