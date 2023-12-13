$LOAD_PATH.unshift("#{BASE_DIR}/lib")

require 'validation/validation_service'

include Qantas::Pipeline
include Qantas::Pipeline::Validation

RSpec.describe ServiceContainer do
  def _get_instance
    ServiceContainer.new
  end

  context '.initialize' do
    it 'can create instance' do
      instance = _get_instance
      expect(instance).not_to be nil
    end
  end

  context 'default instance' do
    it 'default instance is not null' do
      instance = ServiceContainer.instance

      expect(instance).not_to be nil
    end
  end

  context 'can find services by type' do
    it 'one service' do
      instance = ServiceContainer.instance

      services = instance.get_service(ValidationService)

      expect(services).not_to be nil
    end

    it 'many services' do
      instance = ServiceContainer.instance

      services = instance.get_services(ValidationService)

      expect(services).not_to be nil
      expect(services.count > 0).to eq(true)
    end
  end
end
