require 'component'
require 'tasks/pricing_task'

@pricing_task = PricingTask.new

desc "Generates pricing file"
task :generate_pricing do
  @pricing_task.generate_pricing
end
