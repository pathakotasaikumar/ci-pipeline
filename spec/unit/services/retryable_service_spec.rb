$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib/services"))

require 'service_container'
require 'service_base.rb'
require 'retryable_service.rb'

include Qantas::Pipeline
include Qantas::Pipeline::Services

RSpec.describe 'RetryableService' do
  class MyAllowedError < StandardError
  end

  class MyError < StandardError
  end

  def _get_service
    RetryableService.new
  end

  def _get_test_options
    {
      :retry_limit => 10,
      :retry_delay_range => [0, 0]
    }
  end

  context 'initialize' do
    it 'creates an instance' do
      service = _get_service
    end

    it 'default options' do
      service = _get_service

      result = service.default_options

      Log.debug "Result from test:"
      Log.debug result.to_yaml

      expect(result).not_to be(nil)

      expect(result[:retry_limit]).to eq(20)
      expect(result[:retry_delay_range]).to eq([3, 15])
    end
  end

  context '._get_retry_delay' do
    it 'returns random value from array' do
      instance = ServiceContainer.instance
      service = instance.get_service(RetryableService)

      # _get_retry_delay shoudl generate random between min / max
      (1..50).each do |index|
        min = index + rand(index)
        max = min + rand(index)

        Log.debug " expecting (#{min}, #{max})"
        delays = []

        (1..15).each do |try_index|
          result = service.__send__(
            :_get_retry_delay,
            options: {
              retry_delay_range: [min, max]
            }
          )

          delays << result

          expect(result >= min).to be(true)
          expect(result <= max).to be(true)
        end

        Log.debug " - got: #{delays.join(',')}"
      end
    end

    it 'raises on incorrect values' do
      instance = ServiceContainer.instance
      service  = instance.get_service(RetryableService)

      expect {
        service.__send__(:_get_retry_delay, options: {})
      }.to raise_error(/delay_range is not defined/)

      expect {
        service.__send__(
          :_get_retry_delay,
          options: {
            retry_delay_range: [10]
          }
        )
      }.to raise_error(/delay_range should be an array of two values/)

      expect {
        service.__send__(
          :_get_retry_delay,
          options: {
            retry_delay_range: [20, 10]
          }
        )
      }.to raise_error(/first value should be less than second value/)
    end
  end

  context 'default instance' do
    it 'default instance is not null' do
      instance = ServiceContainer.instance
      service = instance.get_service(RetryableService)

      expect(service).not_to be nil
      expect(service.class).to eq(RetryableService)
    end
  end

  context '.exec_with_retry' do
    it 'can execute' do
      service = _get_service
      retry_options = _get_test_options

      retry_limit = 100

      retry_options[:retry_limit] = retry_limit
      return_value = rand(100)

      result = service.exec_with_retry(options: retry_options) {
        Log.info "Simple execution"
        next return_value
      }

      expect(result).not_to be(nil)

      expect(result[:retry_limit]).to eq(retry_limit)
      expect(result[:result_value]).to eq(return_value)
      expect(result[:result_try]).to eq(1)
    end

    it 'raises on empty block' do
      service = _get_service

      expect {
        service.exec_with_retry()
      }.to raise_error(/&block should be giving/)
    end

    it 'executes on random failures' do
      service = _get_service
      retry_options = _get_test_options
      max_iteration = 10

      (0..max_iteration).each do |index|
        Log.info "[#{index}/#{max_iteration}] random retry..."

        result = service.exec_with_retry(options: retry_options) {
          rnd_value = rand(10)
          if rnd_value < 3
            raise "Wrong value: #{rnd_value}"
          end

          next rnd_value
        }

        Log.info "[#{index}/#{max_iteration}] random result:"
        Log.debug result.to_yaml
      end
    end

    it 'raises exception on limit on reached limit' do
      service = _get_service
      retry_options = _get_test_options

      retry_options[:retry_delay] = 0.01

      expect {
        result = service.exec_with_retry(options: retry_options) {
          raise "Annoying API, raising error"
        }
      }.to raise_error(ReTryPipelineError, /Reached(.+)retry attempts/)
    end

    it 'allows exception types for retry' do
      service = _get_service
      retry_options = _get_test_options

      retry_options[:retry_delay] = 0.01
      retry_options[:allowed_exceptions] = [
        StandardError,
        MyAllowedError
      ]

      current_try = 0

      expect {
        result = service.exec_with_retry(options: retry_options) {
          current_try = current_try + 1

          if current_try < 3
            raise StandardError.new, "StandardError, retry value: #{current_try}"
          end

          if current_try < 6
            raise MyAllowedError.new, "MyAllowedError, retry value: #{current_try}"
          end

          raise MyError.new, "Very wrong value: #{current_try}"
        }
      }.to raise_error(MyError, /Very wrong value/)
    end

    it 'allows exception messages for retry' do
      service = _get_service
      retry_options = _get_test_options

      retry_options[:retry_delay] = 0.01
      retry_options[:allowed_exceptions] = [
        MyAllowedError
      ]

      retry_options[:allowed_exception_messages] = [
        /rate error/,
        /RATE error/
      ]

      current_try = 0

      expect {
        result = service.exec_with_retry(options: retry_options) {
          current_try = current_try + 1

          if current_try < 3
            raise MyAllowedError.new "StandardError, retry value: #{current_try}"
          end

          if current_try < 6
            raise "rate error, retry value: #{current_try}"
          end

          if current_try < 8
            raise "RATE error, retry value: #{current_try}"
          end

          raise MyError.new, "Very wrong value: #{current_try}"
        }
      }.to raise_error(MyError, /Very wrong value/)
    end

    it 'fails on unexpected exception messages for retry' do
      service = _get_service
      retry_options = _get_test_options

      retry_options[:retry_delay] = 0.01
      retry_options[:allowed_exceptions] = [
        MyAllowedError
      ]

      retry_options[:allowed_exception_messages] = [
        /rate error/
      ]

      current_try = 0

      expect {
        result = service.exec_with_retry(options: retry_options) {
          current_try = current_try + 1

          if current_try < 3
            raise MyAllowedError.new "StandardError, retry value: #{current_try}"
          end

          if current_try < 6
            raise "rate error, retry value: #{current_try}"
          end

          if current_try < 8
            raise "UNEXPECTED error, retry value: #{current_try}"
          end

          raise MyError.new, "Very wrong value: #{current_try}"
        }
      }.to raise_error(StandardError, /UNEXPECTED/)
    end
  end
end
