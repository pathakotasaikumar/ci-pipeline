$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib"))

require 'tasks/pricing_task.rb'
require "pricing/ec2"

RSpec.describe Action do
  def _get_task
    result = PricingTask.new
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

      expect(task.name).to eq("pricing")
    end
  end

  context '.generate_pricing' do
    it 'generates pricing file' do
      task = _get_task

      allow(Pricing::EC2).to receive(:generate_pricing_file)

      expect { task.generate_pricing }.not_to raise_error
    end
  end
end
