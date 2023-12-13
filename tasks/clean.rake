require 'component'
require 'runner'
require 'tasks/clean_task'

namespace :clean do

  @clean_task = CleanTask.new

  desc "Executes all clean up tasks"
  task :all do
    @clean_task.all
  end

  desc "Clean app logs"
  task :logs do
    @clean_task.logs
  end

  desc "Clean app context"
  task :context do
    @clean_task.context
  end

  desc "Clean app artefacts"
  task :artefacts do
    @clean_task.artefacts
  end

  desc "Clean cloudformation - nuclear option"
  task :cloudformation do
    @clean_task.cloudformation
  end

end

task :clean => ['clean:all']