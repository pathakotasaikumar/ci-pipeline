require 'component'
require 'consumable'
require 'runner'
require 'tasks/release_task'

namespace :release do

  @release_task = ReleaseTask.new

  task :check_state do
    @release_task.check_state
  end

  task :check_service_now  do
    @release_task.check_service_now
  end

  task :load_components do
    @release_task.load_components
  end

  task :pre_release_actions do
    @release_task.pre_release_actions
  end

  task :components do |t, args|
    @release_task.components
  end

  task :post_release_actions do
    @release_task.post_release_actions
  end
end

desc "Release components"
task :release do
  begin 
    @release_task.release  
  rescue => e
    raise @release_task.get_error_report(e)
  end
end
