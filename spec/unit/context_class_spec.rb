$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib"))
require 'context_class.rb'

RSpec.describe ContextClass do
  context '.initialize' do
    it 'creates new dummy instance' do
      expect {
        context = ContextClass.new(
          bucket: Defaults.pipeline_bucket_name,
          storage_type: 'dummy',
          plan_key: Defaults.plan_key,
          branch_name: Defaults.branch,
          build_number: Defaults.build,
          environment: Defaults.environment
        )
      }.not_to raise_error
    end

    it 'creates new instance' do
      expect {
        context = ContextClass.new(
          bucket: Defaults.pipeline_bucket_name,
          storage_type: 'normal',
          plan_key: Defaults.plan_key,
          branch_name: Defaults.branch,
          build_number: Defaults.build,
          environment: Defaults.environment
        )
      }.not_to raise_error
    end
  end

  context '.flush' do
    it 'flushes' do
      context = ContextClass.new(
        bucket: Defaults.pipeline_bucket_name,
        storage_type: 'dummy',
        plan_key: Defaults.plan_key,
        branch_name: Defaults.branch,
        build_number: Defaults.build,
        environment: Defaults.environment
      )

      context.flush
    end
  end
end # RSpec.describe
