require 'rake'
require 'rake/packagetask'
require 'component_validator'
require 'util/archive'
require 'util/stat_helper'
require 'util/yaml_include'
require 'tasks/validate_task'

include Util::Archive

namespace :validate do

  @validate_task = ValidateTask.new

  desc "Perform artefact validation"
  task :all do
    @validate_task.all
  end
end

desc "Perform artefact validation"
task :validate => ['upload:all']

