require "#{BASE_DIR}/lib/errors/pipeline_error"
require "#{BASE_DIR}/lib/errors/pipeline_aggregate_error"

include Qantas::Pipeline::Errors

module Qantas
  module Pipeline
    module Services
      # service renders errors in a nice, human-readable way
      # supports built-in Ruby errors, PipelineError and PipelineAggregateError errors
      class ErrorInfoService < ServiceBase
        # description of the service
        # @see ServiceBase#description
        def description
          'Service to render and report pipeline errors in a nice way'
        end

        # return human-readable string for the giving error
        # by default this method never raises errors so that it an be used safely everywhere in the pipeline
        # iall trace would normally go to .warn()/error() log output
        # @param error [Exception] any error type; Exception, PipelineError or PipelineAggregateError
        # @param raise_on_error [Boolean] false by default, indicates if it should raise an error
        def to_pretty_print(error, raise_on_error = false)
          begin
            result = []

            # nil case
            if error.nil?
              _render_nil_error(result, error)
              return _new_line_join(result)
            end

            # PipelineAggregateError
            if error.is_a?(PipelineAggregateError)
              _render_pipeline_aggregate_error(result, error)
              return _new_line_join(result)
            end

            # PipelineError
            if error.is_a?(PipelineError)
              _render_pipeline_error(result, error)
              return _new_line_join(result)
            end

            # others
            if error.is_a?(Exception)
              _render_generic_error(result, error)
              return _new_line_join(result)
            end

            # warn if no suitable renderer was found, never fail
            Log.warn("Cannot detect supported error type for error - #{error.class} - #{error.inspect}")
          rescue => e
            Log.error("Error while rendering error report - #{e.inspect}")

            if raise_on_error == true
              Log.debug("raise_on_error == #{raise_on_error}, re-raising error - #{e.inspect}")
              raise e
            end
          end
        end

        private

        def _render_nil_error(result, error)
          result << 'error is nil object'
        end

        def _render_pipeline_aggregate_error(result, error)
          result << _get_aggregate_error_header(error)

          all_errors_count = error.error_count
          errors_index = 0
          error.errors.each do |inner_error|
            # just in case we mixed up errors array, report without failure
            if !inner_error.is_a?(Exception)
              Log.error("Expected object of type Exception, got #{inner_error.class} as #{inner_error.inspect}")
              next;
            end

            inner_error_values = []
            _render_pipeline_error(inner_error_values, inner_error)

            inner_error_report = _new_line_join(inner_error_values)

            result << " [#{errors_index + 1}/#{all_errors_count}] #{inner_error_report}"
            errors_index = errors_index + 1
          end
        end

        def _render_pipeline_error(result, error)
          result << _new_line_join([
                                     _get_generic_error_header(error),

                                     _get_pipeline_error_id(error),
                                     _get_pipeline_error_component_name(error),
                                     _get_pipeline_error_decription(error),
                                     _get_pipeline_error_help_link(error),

                                     _get_generic_error_backtrace(error)
                                   ])
        end

        def _render_generic_error(result, error)
          result << _new_line_join([
                                     _get_generic_error_header(error),
                                     _get_generic_error_backtrace(error)
                                   ])
        end

        def _get_pipeline_error_component_name(error)
          if error.respond_to?(:component_name) && !error.component_name.to_s.empty?
            return "   - component name: #{error.component_name}"
          end

          nil
        end

        def _get_pipeline_error_id(error)
          if error.respond_to?(:id) && !error.id.to_s.empty?
            return "   - id: #{error.id}"
          end

          nil
        end

        def _get_pipeline_error_decription(error)
          if error.respond_to?(:description) && !error.description.to_s.empty?
            return "   - description: #{error.description}"
          end

          nil
        end

        def _get_pipeline_error_help_link(error)
          if error.respond_to?(:help_link) && !error.help_link.to_s.empty?
            return "   - help url: #{error.help_link}"
          end

          nil
        end

        def _get_aggregate_error_header(error)
          "#{error.class}, #{error.error_count} errors, #{error.message}"
        end

        def _get_generic_error_header(error)
          "#{error.class}, #{error.message}"
        end

        def _get_generic_error_backtrace(error)
          backtrace = nil

          if !error.backtrace.nil?
            backtrace_message = error.backtrace.join("\n                ")
            return "   - backtrace: #{backtrace_message}"
          end

          nil
        end

        def _safe_join(items, join_value = "\n")
          # trim nil or empty values
          # Ruby's nil.to_s evaluates into an empty string, hence it works
          items.reject { |value| value.to_s.empty? }
               .join(join_value)
        end

        def _new_line_join(items)
          _safe_join(items, "\n")
        end
      end
    end
  end
end
