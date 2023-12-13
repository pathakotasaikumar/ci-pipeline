$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib"))
require 'tasks/validate_task.rb'
require 'component'
require 'component_validator'
require 'util/yaml_include'
require 'util/archive'
require 'util/stat_helper'

RSpec.describe ValidateTask do
  def _get_task
    result = ValidateTask.new

    result
  end

  context '.instantiate' do
    it 'can create an instance' do
      task = _get_task

      expect(task).not_to eq(nil)
    end
  end

  context '.name' do
    it 'returns value' do
      task = _get_task

      expect(task.name).to eq("validate")
    end
  end

  context '.all' do
    it 'calls validate' do
      task = _get_task

      allow(task).to receive(:validate)
      expect(task).to receive(:validate).once

      task.all
    end
  end
end
