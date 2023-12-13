require 'component'
require 'runner'
require_relative 'base_task'
require_relative 'upload_task'

class ValidateTask < UploadTask
  def name
    "validate"
  end

  def validate
    super
  end

  def all
    validate
  end
end
