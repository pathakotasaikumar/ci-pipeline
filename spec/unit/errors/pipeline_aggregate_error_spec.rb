require "#{BASE_DIR}/lib/errors/pipeline_error"
require "#{BASE_DIR}/lib/errors/pipeline_aggregate_error"

include Qantas::Pipeline::Errors

RSpec.describe PipelineAggregateError do
  context '.initialize' do
    it 'can create' do
      # nil
      err1 = PipelineAggregateError.new 'my-task-error1'
      err1_string = "#{err1.to_s}"

      expect(err1).not_to be(nil)
      expect(err1.errors).to eq([])
      expect(err1.error_count).to eq(0)

      expect(err1.message).to eq('my-task-error1')
      expect(err1_string).to eq('my-task-error1')

      # empty array of errors
      err2 = PipelineAggregateError.new("my-task-error2", [])
      err2_string = "#{err2}"

      expect(err2).not_to be(nil)
      expect(err2.errors).to eq([])
      expect(err2.error_count).to eq(0)
      expect(err2_string).to eq('my-task-error2')

      # array with actual values
      err3 = PipelineAggregateError.new 'my-task-error3', [
        ArgumentError.new('value1 is null or empty'),
        ArgumentError.new('value2 is null or empty. Please use 42 as a default value')
      ]
      err3_string = "#{err3}"

      Log.error(err3_string)

      expect(err3).not_to be(nil)
      expect(err3.error_count).to eq(2)
      expect(err3.errors.count).to eq(2)
      expect(err3_string).to eq('my-task-error3')
    end
  end
end # RSpec.describe
