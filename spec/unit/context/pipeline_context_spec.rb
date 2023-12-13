$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib/context/"))
$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib/context/storage"))
require 'pipeline_context.rb'
require 's3_state_storage.rb'
RSpec.describe PipelineContext do
  before(:context) do
    @sections = {
      ams: 'ams01',
      qda: 'c031',
      as: '01',
      branch: 'master',
      ase: 'dev',
      build: '05',
      env: 'prod'
    }
  end

  context '.variable' do
    it 'calls variable' do
      dummy_storage = double(Object)

      allow(dummy_storage).to receive(:variable).with('name', :undef)
      allow(dummy_storage).to receive(:variable).with('name', 'Smith')

      context = PipelineContext.new(dummy_storage, @sections)
      context.instance_variable_set(:@context, dummy_storage)

      context.variable('name')
      context.variable('name', 'Smith')
    end
  end

  context '.set_variables' do
    it 'calls set_variables' do
      dummy_storage = double(Object)

      allow(dummy_storage).to receive(:set_variables).with({})
      allow(dummy_storage).to receive(:set_variables).with({ 'a' => 1 })

      context = PipelineContext.new(dummy_storage, @sections)
      context.instance_variable_set(:@context, dummy_storage)

      context.set_variables({})
      context.set_variables({ 'a' => 1 })
    end
  end

  context '.state' do
    it 'returns state' do
      dummy_storage = double(Object)

      allow(dummy_storage).to receive(:variable).with('State', 'start')

      context = PipelineContext.new(dummy_storage, @sections)
      context.instance_variable_set(:@context, dummy_storage)

      context.state
    end

    it 'sets state' do
      dummy_storage = double(Object)

      allow(dummy_storage).to receive(:set_variables).with({ 'State' => 'new state' })

      context = PipelineContext.new(dummy_storage, @sections)
      context.instance_variable_set(:@context, dummy_storage)

      context.state = 'new state'
    end
  end

  context '.flush' do
    it 'sets state' do
      dummy_storage = double(Object)

      allow(dummy_storage).to receive(:flush)

      context = PipelineContext.new(dummy_storage, @sections)
      context.instance_variable_set(:@context, dummy_storage)

      context.flush
    end
  end

  context '.snow' do
    it 'sets snow_release_id' do
      dummy_storage = double(Object)

      allow(dummy_storage).to receive(:set_variables).with({ 'ReleaseId' => 'new id' })

      context = PipelineContext.new(dummy_storage, @sections)
      context.instance_variable_set(:@context, dummy_storage)

      context.snow_release_id = 'new id'
    end

    it 'returns snow_change_id' do
      dummy_storage = double(Object)

      allow(dummy_storage).to receive(:variable).with('ChangeId', nil)

      context = PipelineContext.new(dummy_storage, @sections)
      context.instance_variable_set(:@context, dummy_storage)

      context.snow_change_id
    end

    it 'sets snow_release_id' do
      dummy_storage = double(Object)

      allow(dummy_storage).to receive(:set_variables).with({ 'ChangeId' => 'new change id' })

      context = PipelineContext.new(dummy_storage, @sections)
      context.instance_variable_set(:@context, dummy_storage)

      context.snow_change_id = 'new change id'
    end

    it 'returns snow_build_user' do
      dummy_storage = double(Object)

      allow(dummy_storage).to receive(:variable).with('BuildUser', nil)

      context = PipelineContext.new(dummy_storage, @sections)
      context.instance_variable_set(:@context, dummy_storage)

      context.snow_build_user
    end

    it 'sets snow_build_user' do
      dummy_storage = double(Object)

      allow(dummy_storage).to receive(:set_variables).with({ 'BuildUser' => 'new user id' })

      context = PipelineContext.new(dummy_storage, @sections)
      context.instance_variable_set(:@context, dummy_storage)

      context.snow_build_user = 'new user id'
    end
  end
end # RSpec.describe
