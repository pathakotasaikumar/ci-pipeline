$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib"))

require 'tasks/base_task.rb'
require 'component'
require 'consumable'
require 'runner'
require 'util/archive'
require 'util/stat_helper'

RSpec.describe BaseTask do
  def _get_task
    BaseTask.new
  end

  context '.instantiate' do
    it 'can create an instance' do
      task = _get_task

      expect(task).not_to eq(nil)
    end
  end

  context '.env' do
    it 'can get env' do
      task = _get_task

      expect(task.send(:_env)).to eq(ENV)
    end
  end
end
