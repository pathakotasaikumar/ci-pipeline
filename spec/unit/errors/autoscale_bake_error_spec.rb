require "#{BASE_DIR}/lib/errors/autoscale_bake_error"

include Qantas::Pipeline::Errors

RSpec.describe PipelineError do
  context '.initialize' do
    it 'can create' do
      err = AutoScaleBakeError.new
      expect(err).not_to be(nil)
    end

    it 'has correct metadata' do
      err = AutoScaleBakeError.new

      expect(err.id).to eq(101)
      expect(err.description).to eq("aws/autoscale component failed to bake AMI, check 'aws/autoscale failures' page")
      expect(err.help_link).to eq('https://confluence.qantas.com.au/pages/viewpage.action?pageId=114798610')
    end
  end
end # RSpec.describe
