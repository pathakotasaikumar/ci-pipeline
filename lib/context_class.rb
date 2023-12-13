require 'context/asir_context'
require 'context/component_context'
require 'context/context_storage'
require 'context/environment_context'
require 'context/kms_context'
require 'context/persist_context'
require 'context/pipeline_context'
require 'context/s3_context'
require 'defaults'

class ContextClass
  attr_reader :asir
  attr_reader :component
  attr_reader :environment
  attr_reader :kms
  attr_reader :persist
  attr_reader :pipeline
  attr_reader :s3

  def initialize(
    bucket:,
    storage_type:,
    plan_key:,
    branch_name:,
    build_number:,
    environment:
  )
    Defaults.set_sections(plan_key, branch_name, build_number, environment)

    @storage_type = storage_type

    if storage_type == 'dummy'
      require_relative 'context/storage/dummy_state_storage'
      state_storage = DummyStateStorage.new
      safe_state_storage = state_storage
    else
      require_relative 'context/storage/s3_state_storage'
      require_relative 'context/storage/cloudformation_state_storage'
      state_storage = S3StateStorage.new(bucket)
      safe_state_storage = CloudFormationStateStorage.new
    end

    @asir = AsirContext.new(state_storage, Defaults.sections)
    @component = ComponentContext.new(state_storage, Defaults.sections)
    @environment = EnvironmentContext.new(state_storage, Defaults.sections)
    @kms = KmsContext.new(state_storage, Defaults.sections)
    @persist = PersistContext.new(safe_state_storage, Defaults.sections)
    @pipeline = PipelineContext.new(state_storage, Defaults.sections)
    @s3 = S3Context.new
  end

  def flush
    @asir.flush
    @component.flush
    @environment.flush
    @kms.flush
    @persist.flush
    @pipeline.flush
    @s3.flush
  end
end
