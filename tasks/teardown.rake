require 'component'
require 'consumable'
require 'runner'
require 'tasks/teardown_task'

namespace :teardown do

  @teardown_task = TeardownTask.new

  task :check_state do
    @teardown_task.check_state
  end

  task :check_service_now do
    @teardown_task.check_service_now
  end

  task :load_components  do
    @teardown_task.load_components
  end

  task :pre_teardown_actions do
    @teardown_task.pre_release_actions
  end

  task :components do 
    @teardown_task.components
  end

  task :post_teardown_actions do
    @teardown_task.post_teardown_actions
  end

end

desc "Teardown components"
task :teardown do
  begin 
    @teardown_task.teardown  
  rescue => e
    raise @teardown_task.get_error_report(e)
  end
end
