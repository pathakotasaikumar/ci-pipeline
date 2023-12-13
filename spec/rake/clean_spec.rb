$LOAD_PATH.unshift("#{BASE_DIR}/lib")
require 'rake'

RSpec.describe 'rake' do
  # getting shared context for the tests
  require_relative 'shared_context.rb'

  describe 'clean' do
    let(:task_paths) { ['clean'] }
    let(:task_name) { 'clean:all' }
    include_context 'rake'

    # see upload_spec.rb on how to implement rake task testing
  end
end # RSpec.describe
