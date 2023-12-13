require "#{BASE_DIR}/lib/errors/pipeline_error"
require "#{BASE_DIR}/lib/errors/pipeline_error"

include Qantas::Pipeline::Errors

RSpec.describe PipelineError do
  context '.initialize' do
    it 'can create' do
      err = PipelineError.new
      expect(err).not_to be(nil)
    end
  end
end # RSpec.describe
