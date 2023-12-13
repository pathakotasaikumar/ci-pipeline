require 'validation/validation_service'

include Qantas::Pipeline::Validation

RSpec.describe "ValidationService" do
  def _get_service
    ValidationService.new
  end

  context '.instantiate' do
    it 'can create an instance' do
      service = _get_service

      expect(service).not_to be(nil)
    end
  end

  context '.validate' do
    it 'can validate empty data' do
      service = _get_service

      data = ValidationData.new

      result = service.validate(data: data)

      expect(result).not_to be(nil)
      expect(result.valid).to eq(true)
      expect(result.results.count == 0).to eq(true)
    end

    it 'raise on non-ValidationData input' do
      service = _get_service

      data = {}

      expect {
        service.validate(data: data)
      }.to raise_error(/data should be of type ValidationData/)
    end
  end

  context '.api' do
    it 'can load validators' do
      service = _get_service

      data = ValidationData.new
      validators = service.send(:_validators)

      expect(validators).not_to be(nil)
      expect(validators.count > 0).to eq(true)
    end
  end
end
