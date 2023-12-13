$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib/services"))
require 'service_base.rb'

include Qantas::Pipeline::Services

RSpec.describe 'ServiceBase' do
  def _get_service
    ServiceBase.new
  end

  context '.initialized' do
    it 'creates an instance' do
      service = _get_service
    end

    it 'has metadata' do
      service = _get_service

      # default metadata - name / description
      expect(service.name).to eq(service.class.to_s)
      expect(service.description).to eq('A base class for pipeline-specific services')
    end
  end
end
