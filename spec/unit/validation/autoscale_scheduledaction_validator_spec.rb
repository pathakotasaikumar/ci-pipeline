require 'validation/validation_service'
require 'validation/autoscale_scheduledaction_validator'
require 'yaml'
require 'consumable'
require 'core/app_container_info'
require_relative 'validation_spec_helper'

include Qantas::Pipeline::Core
include Qantas::Pipeline::Validation

RSpec.describe AutoscaleSheduledActionValidator do
  include_context 'shared_validation_context'

  before(:context) do
    @spec_file_path = "#{__FILE__}"

    @pass_components = ValidationSpecHelper.get_pass_components(@spec_file_path)
    @fail_components = ValidationSpecHelper.get_fail_components(@spec_file_path)
  end

  def _get_service
    AutoscaleSheduledActionValidator.new
  end

  context '.instantiate' do
    it 'can create an instance' do
      service = _get_service

      expect(service).not_to be(nil)
    end
  end

  context '.validate' do
    it 'pass' do
      service = _get_service

      standard_pass_tests(
        service: service,
        spec_file: @spec_file_path
      )
    end

    it 'fail' do
      service = _get_service

      standard_fail_tests(
        service: service,
        spec_file: @spec_file_path
      )
    end
  end
end
