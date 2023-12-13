$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib/context"))
require 'persist_context.rb'

RSpec.describe PersistContext do
  before(:context) do
    @sections = {
      ams: 'ams01',
      qda: 'c031',
      as: '01',
      branch: 'master',
      ase: 'dev',
      build: '05'
    }
  end

  context '.initialise' do
    it 'creates an instance' do
      dummy_storage = double(Object)

      expect {
        PersistContext.new(
          dummy_storage, @sections
        )
      }.not_to raise_error
    end
  end

  context '._load_active_builds_context' do
    it 'loads state' do
      dummy_storage = double(Object)

      context = PersistContext.new(
        dummy_storage, @sections
      )
      allow(context).to receive(:_get_backoff_sleep_time).and_return(0.05)

      allow(dummy_storage).to receive(:load) .and_return({ 'a' => 1 })

      result = context._load_active_builds_context('test-component')

      expect(result).to be_kind_of(Hash)
      expect(result['a']).to eq(1)
    end
  end

  context 'released_build_number' do
    it 'loads released_build_number' do
      dummy_storage = double(Object)

      context = PersistContext.new(
        dummy_storage, @sections
      )
      allow(context).to receive(:_get_backoff_sleep_time).and_return(0.05)

      allow(dummy_storage).to receive(:load) .and_return({
        'a' => 1,
        'ReleasedBuildNumber' => 42
      })

      expect(context.released_build_number).to eq(42)
    end

    it 'saves released_build_number' do
      dummy_storage = double(Object)

      context = PersistContext.new(
        dummy_storage, @sections
      )
      allow(context).to receive(:_get_backoff_sleep_time).and_return(0.05)

      released_path = context.send(:release_path)
      expect(dummy_storage).to receive(:save).exactly(1).times
                                             .with(released_path, { 'ReleasedBuildNumber' => 142 })

      allow(PipelineMetadataService).to receive(:save_metadata)
      context.released_build_number = 142
    end

    it 'fails to saves released_build_number' do
      dummy_storage = double(Object)

      context = PersistContext.new(
        dummy_storage, @sections
      )
      allow(context).to receive(:_get_backoff_sleep_time).and_return(0.05)

      released_path = context.send(:release_path)
      expect(dummy_storage).to receive(:save).exactly(1).times
                                             .with(released_path, { 'ReleasedBuildNumber' => 142 })

      allow(PipelineMetadataService).to receive(:save_metadata).and_raise(RuntimeError)
      expect { context.released_build_number = 142 }.to raise_exception(/Failed to update released builds context/)
    end

    it 'saves nil released_build_number' do
      dummy_storage = double(Object)

      context = PersistContext.new(
        dummy_storage, @sections
      )
      allow(context).to receive(:_get_backoff_sleep_time).and_return(0.05)

      released_path = context.send(:release_path)
      expect(dummy_storage).to receive(:save).exactly(1).times
                                             .with(released_path, nil)

      allow(PipelineMetadataService).to receive(:save_metadata)
      context.released_build_number = nil
    end
  end

  context 'build operations' do
    it 'can add active build' do
      dummy_storage = double(Object)
      allow(dummy_storage).to receive(:save)

      context = PersistContext.new(
        dummy_storage, @sections
      )
      allow(context).to receive(:_get_backoff_sleep_time).and_return(0.05)

      allow(dummy_storage).to receive(:load) .and_return({
        'a' => 1,
        'ActiveBuilds' => { 1 => [1, 2, 3] }
      })

      allow(PipelineMetadataService).to receive(:save_metadata)

      active_builds = context.add_active_build('test-component', 42, 40)
      expect(active_builds).to eq([40])

      active_builds = context.add_active_build('test-component', 42, 41)
      expect(active_builds).to eq([41])

      active_builds = context.add_active_build('test-component', 1, 1)
      expect(active_builds).to eq([1, 2, 3])

      active_builds = context.add_active_build('test-component', 1, 4)
      expect(active_builds).to eq([1, 2, 3, 4])
    end

    it 'failed to add active build' do
      dummy_storage = double(Object)
      allow(dummy_storage).to receive(:save)

      context = PersistContext.new(
        dummy_storage, @sections
      )
      allow(context).to receive(:_get_backoff_sleep_time).and_return(0.05)

      allow(dummy_storage).to receive(:load) .and_return({
        'a' => 1,
        'ActiveBuilds' => { 1 => [1, 2, 3] }
      })

      allow(PipelineMetadataService).to receive(:save_metadata).and_raise(RuntimeError)

      expect { context.add_active_build('test-component', 42, 40) }.to raise_exception(/Failed to update active builds for component "test-component"/)
    end

    it 'can remove active build' do
      dummy_storage = double(Object)
      allow(dummy_storage).to receive(:save)

      context = PersistContext.new(
        dummy_storage, @sections
      )
      allow(context).to receive(:_get_backoff_sleep_time).and_return(0.05)

      allow(dummy_storage).to receive(:load) .and_return({
        'a' => 1,
        'ActiveBuilds' => { 1 => [1, 2, 3] }
      })
      allow(PipelineMetadataService).to receive(:save_metadata)

      active_builds = context.remove_active_build('test-component', 42, 40)
      expect(active_builds).to eq([])

      active_builds = context.remove_active_build('test-component', 1, 4)
      expect(active_builds).to eq([1, 2, 3])

      active_builds = context.remove_active_build('test-component', 1, 2)
      expect(active_builds).to eq([1, 3])

      active_builds = context.remove_active_build('test-component', 1, 3)
      expect(active_builds).to eq([1, 2])
    end

    it 'fails to remove active build' do
      dummy_storage = double(Object)
      allow(dummy_storage).to receive(:save)

      context = PersistContext.new(
        dummy_storage, @sections
      )
      new_context = {
        'a' => 1,
        'ActiveBuilds' => { 1 => [1, 2, 3] }
      }
      allow(context).to receive(:_get_backoff_sleep_time).and_return(0.05)
      allow(dummy_storage).to receive(:load) .and_return(new_context)

      allow(PipelineMetadataService).to receive(:save_metadata).with(
        context_name: anything,
        context: new_context
      ).and_raise(RuntimeError)

      expect { context.remove_active_build('test-component', 42, 40) }.to raise_exception(/Failed to remove the active builds for component "test-component"/)
    end

    it 'raises exception on _update_active_builds_context' do
      save_index = 0

      dummy_storage = double(Object)
      allow(dummy_storage).to receive(:save) { raise 'error saving context' if (save_index += 1) <= 1 }

      context = PersistContext.new(
        dummy_storage, @sections
      )
      allow(context).to receive(:_get_backoff_sleep_time).and_return(0.05)

      allow(PipelineMetadataService).to receive(:save_metadata)

      context.instance_variable_set(:@save_min_attempt_backoff, 1)
      context.instance_variable_set(:@save_max_attempt_backoff, 2)
      context.instance_variable_set(:@save_attempts_count, 2)

      allow(dummy_storage).to receive(:load) .and_return({
        'a' => 1,
        'ActiveBuilds' => { 1 => [1, 2, 3] }
      })

      active_builds = context.remove_active_build('test-component', 42, 40)
      expect(active_builds).to eq([])

      active_builds = context.remove_active_build('test-component', 1, 4)
      expect(active_builds).to eq([1, 2, 3])

      active_builds = context.remove_active_build('test-component', 1, 2)
      expect(active_builds).to eq([1, 3])

      active_builds = context.remove_active_build('test-component', 1, 3)
      expect(active_builds).to eq([1, 2])
    end
  end

  context 'get_active_builds' do
    it 'loads active builds' do
      dummy_storage = double(Object)

      context = PersistContext.new(
        dummy_storage, @sections
      )
      allow(context).to receive(:_get_backoff_sleep_time).and_return(0.05)

      allow(dummy_storage).to receive(:load) .and_return({
        'a' => 1,
        'ActiveBuilds' => { 1 => [1, 2, 3] }
      })

      expect(context.get_active_builds('test-component', 1)).to eq([1, 2, 3])
      expect(context.get_active_builds('test-component', 2)).to eq([])
    end

    it 'loads empty active builds' do
      dummy_storage = double(Object)

      context = PersistContext.new(
        dummy_storage, @sections
      )
      allow(context).to receive(:_get_backoff_sleep_time).and_return(0.05)

      allow(dummy_storage).to receive(:load) .and_return({
        'a' => 1
      })

      expect(context.get_active_builds('test-component', 1)).to eq([])
      expect(context.get_active_builds('test-component', 2)).to eq([])
    end
  end

  context '._active_builds_path' do
    it 'returns build paths' do
      dummy_storage = double(Object)

      context = PersistContext.new(
        dummy_storage, @sections
      )
      allow(context).to receive(:_get_backoff_sleep_time).and_return(0.05)

      result = context.send(:_active_builds_path, "test-component")

      expect(result).to be_kind_of(Array)

      expect(result[0]).to eq(@sections[:ams])
      expect(result[1]).to eq(@sections[:qda])
      expect(result[2]).to eq(@sections[:as])
      expect(result[3]).to eq(@sections[:ase])
      expect(result[4]).to eq(@sections[:branch])
      expect(result[5]).to eq("test-component")
      expect(result[6]).to eq("ActiveBuilds")
    end
  end
end
