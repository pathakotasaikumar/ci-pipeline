module Qantas
  module Pipeline
    module Errors
      # a custom error type to store multiple nested errors
      class PipelineAggregateError < PipelineError
        def initialize(message, errors = nil)
          @message = message
          @errors = errors

          super(message)
        end

        # returns an array of nested errors
        # @return [Array]
        def errors
          if @errors.nil?
            return []
          end

          # we might have other than Exception class objects, trim them early
          @errors.reject { |value| value.nil? || !value.is_a?(Exception) }
        end

        # returns amount of nested errors
        # @return [Exception]
        def error_count
          return errors.count
        end
      end
    end
  end
end
