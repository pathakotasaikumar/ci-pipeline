require 'rake'
require 'rake/packagetask'
require 'component_validator'
require 'util/archive'
require 'util/stat_helper'
require 'util/yaml_include'

require 'tasks/upload_task'

include Util::Archive

namespace :upload do

  @upload_task = UploadTask.new

  desc 'Default task'
  task :all do
    @upload_task.all
  end

  desc 'Prepares environment'
  task :prepare do
    @upload_task.prepare
  end

  desc 'Validate component definitions'
  task :validate do
    @upload_task.validate
  end

  desc "Packages the artefact"
  task :package do
    @upload_task.package
  end

  desc 'Performs compliance checks on the artefact'
  task :compliance do
    @upload_task.compliance
  end

  desc 'Creates the checksum and logs it to CMDB'
  task :checksum do
    @upload_task.compliance
  end

  desc "Uploads the packaged artefacts to the application's S3 bucket"
  task :upload do
    @upload_task.upload
  end

  desc "Cleans up the created payload directory"
  task :clean do
    @upload_task.clean
  end

  desc "Invokes corresponding BambooCD plan"
  task :cdintegration do
    @upload_task.cdintegration
  end
end

desc "Perform artefact upload"
task :upload => ['upload:all']
