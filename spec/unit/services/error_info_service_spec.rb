require "#{BASE_DIR}/lib/errors/pipeline_error"
require "#{BASE_DIR}/lib/services/error_info_service.rb"

include Qantas::Pipeline::Errors
include Qantas::Pipeline::Services

RSpec.describe ErrorInfoService do
  class UnitTestStackDeploymentError < PipelineError
    def initialize(message = nil, error = nil)
      @innerException = error

      super(message)

      @id = 10000
      @description = 'Pipeine could not deploy stack'
      @help_link   = 'https://confluence.qantas.com.au/pages/viewpage.action?pageId=64161715'
    end
  end

  def _get_service
    ErrorInfoService.new
  end

  context '.initialized' do
    it 'creates an instance' do
      service = _get_service
    end

    it 'has metadata' do
      service = _get_service

      # default metadata - name / description
      expect(service.name).to eq(service.class.to_s)
      expect(service.description).to eq('Service to render and report pipeline errors in a nice way')
    end
  end

  context '.to_pretty_print' do
    it 'does not fail on wrong input' do
      service = _get_service

      expect {
        service.to_pretty_print(nil)
      }.not_to raise_error

      expect {
        service.to_pretty_print(1)
      }.not_to raise_error

      expect {
        service.to_pretty_print("1")
      }.not_to raise_error

      expect {
        service.to_pretty_print(ErrorInfoService.new)
      }.not_to raise_error
    end

    it 'does not fail on wrong input' do
      service = _get_service

      allow(service).to receive(:_render_nil_error) .and_raise('Random rendering error!')

      expect {
        service.to_pretty_print(nil)
      }.not_to raise_error
    end

    it 'raises on raise_on_error = true' do
      service = _get_service

      allow(service).to receive(:_render_nil_error) .and_raise('Random rendering error!')

      expect {
        service.to_pretty_print(nil, true)
      }.to raise_error
    end

    it 'renders nil' do
      service = _get_service

      result = service.to_pretty_print(nil)
      expect(result).to eq('error is nil object')
    end

    it 'renders generic error' do
      service = _get_service

      begin
        t = 1 / 0
      rescue => e
        result = service.to_pretty_print(e)

        Log.error(result)

        # general details
        expect(result).to include('ZeroDivisionError, divided by 0')

        # backtrace
        expect(result).to include('- backtrace: /')
      end
    end

    it 'renders wrapped error' do
      service = _get_service

      begin
        t = 1 / 0
      rescue => e
        wrappedError = PipelineError.wrapError(e)

        result = service.to_pretty_print(wrappedError)
        Log.error(result)

        # general details for wrapped error
        expect(result).to include('Qantas::Pipeline::Errors::PipelineError, Wrapped error: divided by 0')

        # backtrace
        expect(result).to include('- backtrace: /')
      end
    end

    it 'renders pipeline error' do
      service = _get_service

      begin
        raise UnitTestStackDeploymentError.new('Failed to deploy stack')
      rescue => e
        result = service.to_pretty_print(e)

        Log.error(result)

        # UnitTestStackDeploymentError details
        expect(result).to include('UnitTestStackDeploymentError, Failed to deploy stack')
        expect(result).to include('- id: 10000')
        expect(result).to include('- description: Pipeine could not deploy stack')
        expect(result).to include('- help url: https://confluence.qantas.com.au/pages/viewpage.action?pageId=64161715')

        # backtrace
        expect(result).to include('- backtrace: /')
      end
    end

    it 'renders aggregate error' do
      service = _get_service

      begin
        err1 = UnitTestStackDeploymentError.new('Failed to deploy stack')
        err2 = PipelineError.new('General pipeline error')
        err3 = PipelineError.wrapError(StandardError.new('BANG!'))

        begin
          t = 1 / 0
        rescue => nativeError
          raise PipelineAggregateError.new('Big bang!', [
                                             err1,
                                             err2,
                                             err3,
                                             "bla",
                                             nativeError
                                           ])
        end
      rescue => e
        result = service.to_pretty_print(e)
        Log.error(result)

        # AggregateError header
        expect(result).to include('Qantas::Pipeline::Errors::PipelineAggregateError, 4 errors, Big bang!')

        # inner errors header
        expect(result).to include('[1/4] UnitTestStackDeploymentError, Failed to deploy stack')
        expect(result).to include('[2/4] Qantas::Pipeline::Errors::PipelineError, General pipeline error')
        expect(result).to include('[3/4] Qantas::Pipeline::Errors::PipelineError, Wrapped error: BANG!')
        expect(result).to include('[4/4] ZeroDivisionError, divided by 0')

        # UnitTestStackDeploymentError details
        expect(result).to include('- id: 10000')
        expect(result).to include('- description: Pipeine could not deploy stack')
        expect(result).to include('- help url: https://confluence.qantas.com.au/pages/viewpage.action?pageId=64161715')

        # backtrace
        expect(result).to include('- backtrace: /')
      end
    end
  end
end
