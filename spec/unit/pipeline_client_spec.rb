$LOAD_PATH.unshift("#{BASE_DIR}/lib")
require 'pipeline_client'

RSpec.describe Runner do
  context ".initialize" do
    it 'can create pipeline client' do
      Defaults.set_pipeline_task('unit-tests')

      # disabling ENV and gem trace under unit tests
      client = PipelineClient.new(
        disable_log_output: true
      )

      expect(client).not_to eq(nil)
    end
  end
end
