module Qantas
  module Pipeline
    module Errors
      # base class for all pipeline related errors
      # provides wrapping capabilities over the builtin Ruby errors
      # enhances errors with additional metadata: id, description, help_link and component_name
      class PipelineError < StandardError
        attr_reader   :innerException

        attr_accessor :component_name
        attr_accessor :description
        attr_accessor :help_link
        attr_accessor :id

        # returns an instance of PipelineError which wraps the giving error of any type
        # @param error [Exception]
        # @return [PipelineError]
        def self.wrapError(error)
          # return wrapper error for the nil values
          if error.nil?
            return PipelineError.new("Wrapped error", nil)
          end

          # re-return PipelineError
          if error.is_a?(PipelineError)
            return error
          end

          # wrap error into enhanced PipelineError
          return PipelineError.new("Wrapped error: #{error.message}", error)
        end

        # @param message [String] error message
        # @param error [Exception] error to wrap up
        def initialize(message = nil, error = nil)
          @innerException = error

          super(message)
        end

        # returns its own backtrace or backtrace of the wrapped error
        # @return [String]
        def backtrace
          if !@innerException.nil?
            return @innerException.backtrace
          end

          super
        end

        # returns its own backtrace_locations or backtrace_locations of the wrapped error
        # @return [Array]
        def backtrace_locations
          if !@innerException.nil?
            return @innerException.backtrace_locations
          end

          super
        end

        # returns its own cause or cause of the wrapped error
        # @return [String]
        def cause
          if !@innerException.nil?
            return @innerException.cause
          end

          super
        end
      end
    end
  end
end
