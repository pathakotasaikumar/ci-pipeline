require 'component'
require 'runner'
require 'tasks/context_task'

namespace :context do

  @context_task = ContextTask.new

  desc "Read context from state storage"
  task :read do
    @context_task.read
  end

  desc "Write context to state storage"
  task :write do |t, args|
    # Reenable this task to ensure that the context can be flushed multiple times per Rake session
    t.reenable

    @context_task.flush
  end

  desc "Get last build number"
  task :last_build do
    # don't have a clean way to export this out
    # chancing our luck tailing the last line
    puts @context_task.last_build
  end

end

