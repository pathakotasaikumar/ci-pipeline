require 'component'
require 'consumable'
require 'runner'
require 'util/archive'

include Util::Archive

require 'tasks/deploy_task'

namespace :deploy do

  @deploy_task = DeployTask.new

  task :check_state do 
    @deploy_task.check_state
  end

  task :check_service_now  do
    @deploy_task.check_service_now
  end

  task :load_components do 
    @deploy_task.load_components
  end

  task :copy_artefacts  do
    @deploy_task.copy_artefacts
  end

  task :print_resource_group do
    @deploy_task.print_resource_group
  end

  # Deploy KMS encryption keys
  task :kms do
    @deploy_task.kms
  end

  # Build component security
  task :load_persistence do
    @deploy_task.load_persistence
  end

  # Deploy component security
  task :security do
    @deploy_task.security
  end

  task :pre_deploy_actions do
    @deploy_task.security    
  end

  task :components do 
    @deploy_task.components   
  end

  task :post_deploy_actions do
    @deploy_task.post_deploy_actions   
  end
end

desc "Deploy components"
task :deploy do
  begin 
    @deploy_task.deploy
  rescue => e
    raise @deploy_task.get_error_report(e)
  end
end

# Alias 'build' to 'deploy' for legacy reasons
# TODO: remove after all plans have been switched to 'deploy'
task :build => ['deploy']