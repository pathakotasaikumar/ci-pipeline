require "#{BASE_DIR}/lib/errors/pipeline_error"
require "#{BASE_DIR}/lib/errors/retry_pipeline_error"

include Qantas::Pipeline::Errors

module Qantas
  module Pipeline
    module Services
      class RetryableService < ServiceBase
        def description
          'Service to provide retryable calls for non-retryable methods'
        end

        # default settings for retry logic
        # CloudFormationHelper.cfn_create_stack() method has the following setup:
        #  - retry_limit: 20,
        #  - retry_delay_range: [3, 15]
        # Try 20 times with random delay between 3 and 15 seconds.
        # Max time = 20 * 15 = 300 sec (10 min)
        @@default_options = {
          :retry_limit => 20,
          :retry_delay_range => [3, 15]
        }

        # returns default options for retry logic
        def default_options
          @@default_options
        end

        # composes default retry options with user-provided
        # @param [Hash] options - hash similar to default_options()
        def _get_options(options: {})
          Log.debug " - default retry options: #{default_options.inspect}"

          result = default_options.merge(options)
          Log.debug " - merged  retry options: #{result.inspect}"

          result
        end

        def _get_retry_delay(options:)
          delay_range = options[:retry_delay_range]

          raise 'delay_range is not defined' if delay_range.nil?
          raise 'delay_range should be an array of two values' if delay_range.count != 2

          min = delay_range[0]
          max = delay_range[1]

          raise "first value should be less than second value, #{min} <= #{max}" if min > max

          rand(min..max)
        end

        # executes giving &block with try-retry logic
        # uses default parameters from .default_options() merges with provides by options:
        # @param [Hash] options - hash similar to default_options()
        # @return [Hash] hash similar to default_options(), use :result_value to get &block execiution result, use :attempts to analyse execution details
        def exec_with_retry(options: {}, &block)
          # always require block to be executed
          if !block_given?
            raise "&block should be giving"
          end

          # result structure to house &block execution value and execution stat:
          # :result_value - block result
          # :attempts - details stat over failed attempts
          result = {
            attempts: []
          }

          opt = _get_options(options: options)

          current_try  = 1
          retry_delay  = _get_retry_delay(options: opt)

          allowed_exceptions         = opt[:allowed_exceptions]
          allowed_exception_messages = opt[:allowed_exception_messages]

          retry_limit = opt[:retry_limit]
          has_exception = false

          # try until we reach retru_count limit
          # analyse current try, then exception raised - type and message
          # make a decision to re-try giving block or re-raise original exception
          while current_try <= retry_limit

            Log.debug " - try #{current_try}/#{retry_limit}"
            current_attempt = {
              :current_try => current_try,
              :retry_limit => retry_limit,
              :retry_delay => retry_delay,
              :exception => nil,
              :success => false
            }

            begin
              result[:result_try] = current_try

              # execute block, analyse results and save it into current_attempt stat
              block_result = block.call
              has_exception = false

              result[:result_value] = block_result

              # do not add result value into attempt history
              # current_attempt[:result_value] = block_result
              current_attempt[:success] = true

              result[:attempts] << current_attempt

              break
            rescue => e
              has_exception = true
              Log.warn " - failed try #{current_try}/#{retry_limit}, error class: #{e.class}, message: #{e}"

              # expected exception clsdd or exception message?
              # methods would return 'nil' of allowed_xxx arrays are empty or not set
              has_allowed_exception         = _expected_error_class?(allowed_exceptions, e, current_try, retry_limit)
              has_allowed_exception_message = _expected_error_message?(allowed_exception_messages, e, current_try, retry_limit)

              # if there is a rule set by excpetion class / message, apply and make decision
              if !has_allowed_exception.nil? || !has_allowed_exception_message.nil?

                # re-raising original exception or exception wasn't expected
                if has_allowed_exception == true || has_allowed_exception_message == true
                  Log.debug " - failed try #{current_try}/#{retry_limit}, has_allowed_exception: #{has_allowed_exception} has_allowed_exception_message: #{has_allowed_exception_message}"
                  Log.debug " - failed try #{current_try}/#{retry_limit}, exception was expected, retrying..."
                else
                  Log.debug " - failed try #{current_try}/#{retry_limit}, has_allowed_exception: #{has_allowed_exception} has_allowed_exception_message: #{has_allowed_exception_message}"
                  Log.debug " - failed try #{current_try}/#{retry_limit}, exception type/message match weren't expected, reraising error: #{e}"
                  raise
                end
              end

              # excption was expected, saving current_attempt data
              # iterating to next retry

              current_attempt[:exception] = e
              current_attempt[:success]   = false
            end

            # saving current_attempt
            result[:attempts] << current_attempt

            # sleeping
            Log.debug " - sleeping try #{current_try}/#{retry_limit}, #{retry_delay} sec"
            sleep retry_delay

            current_try = current_try + 1
            retry_delay = _get_retry_delay(options: opt)
          end

          # still exception after all our effort
          # we reached retry attempts, raising pipeline exception
          if has_exception == true
            retry_limit_exception = "Reached #{current_try}/#{retry_limit} retry attempts. Raising exception"

            Log.error retry_limit_exception
            raise ReTryPipelineError.new, retry_limit_exception
          end

          # return options used in the call + additinal information:
          # :result_try   - when we passed
          # :result_value - outcome of the block execution
          return opt.merge(result)
        end
      end

      # checks if giving exception message is expected
      def _expected_error_message?(allowed_exception_messages, e, current_try, retry_limit)
        result = nil

        if allowed_exception_messages.nil? || allowed_exception_messages.empty?
          return result
        end

        # don't expect this exception message
        if !allowed_exception_messages.nil? && allowed_exception_messages.any?

          allowed_exception_messages.each do |allowed_exception_message|
            # skip empty strings for the sake of stability
            if allowed_exception_message.nil? || allowed_exception_message.to_s.empty?
              next
            end

            # perform matching
            Log.debug " - failed try #{current_try}/#{retry_limit}, matching: '#{allowed_exception_message}' to error '#{e.to_s}'"
            result = !allowed_exception_message.match(e.to_s).nil?

            if result == true
              Log.debug " - failed try #{current_try}/#{retry_limit},     [+] expected exception message match: #{allowed_exception_message}"
              break
            else
              Log.debug " - failed try #{current_try}/#{retry_limit},     [-] didn't match message: #{allowed_exception_message}"
              result = false
            end
          end
        end

        result
      end

      # checks if giving exception class is expected
      def _expected_error_class?(allowed_exceptions, e, current_try, retry_limit)
        result = nil

        if allowed_exceptions.nil? || allowed_exceptions.empty?
          return result
        end

        # don't expect this type of exception
        if !allowed_exceptions.nil?
          if allowed_exceptions.include?(e.class)
            Log.debug " - failed try #{current_try}/#{retry_limit}, [+] expected exception type: #{e.class}"
            result = true
          else
            Log.debug " - failed try #{current_try}/#{retry_limit}, [-] didn't expected exception type: #{e.class}"
            result = false
          end
        end

        result
      end
    end
  end
end
