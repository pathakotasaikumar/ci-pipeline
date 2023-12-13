$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib"))
require 'tasks/clean_task.rb'

RSpec.describe Action do
  def _get_task
    CleanTask.new
  end

  def _get_sections
    {

    }
  end

  context '.instantiate' do
    it 'can create an instance' do
      task = _get_task

      expect(task).not_to eq(nil)
    end
  end

  context '.name' do
    it 'returns value' do
      task = _get_task

      expect(task.name).to eq("clean")
    end
  end

  context '._env' do
    it 'returns value' do
      task = _get_task

      expect(task.send(:_env)).to eq(ENV)
    end
  end

  context '.all' do
    it 'calls sub tasks' do
      task = _get_task

      allow(task).to receive(:_env).and_return({})

      expect(task).to receive(:logs).once
      expect(task).to receive(:context).once
      expect(task).to receive(:artefacts).once

      expect { task.all }.not_to raise_error
    end
  end

  context '.logs' do
    it 'calls context_task.read' do
      task = _get_task

      allow(task).to receive(:_env).and_return({})

      expect(task.context_task).to receive(:read).once
      expect { task.logs }.not_to raise_error
    end

    it 'returns on non-local-dev' do
      task = _get_task

      allow(task).to receive(:_env).and_return({})
      expect { task.logs }.not_to raise_error
    end

    it 'executes on local-dev' do
      task = _get_task

      allow(task).to receive(:_env).and_return({
        'local_dev' => true
      })

      allow(task.context_task).to receive(:read)

      allow(Context).to receive_message_chain('s3.artefact_bucket_name')
      allow(Defaults).to receive_message_chain('sections').and_return(_get_sections)

      allow(FileUtils).to receive(:rm_rf)
      allow(AwsHelper).to receive(:s3_delete_objects)

      expect { task.logs }.not_to raise_error
    end
  end

  context '.context' do
    it 'calls context_task.read' do
      task = _get_task

      allow(task).to receive(:_env).and_return({})

      allow(task.context_task).to receive(:read)

      expect(task.context_task).to receive(:read).once
      expect { task.context }.not_to raise_error
    end

    it 'returns on non-local-dev' do
      task = _get_task

      allow(task.context_task).to receive(:read)

      allow(task).to receive(:_env).and_return({})
      expect { task.context }.not_to raise_error
    end

    it 'executes on local-dev' do
      task = _get_task

      allow(task).to receive(:_env).and_return({
        'local_dev' => true
      })

      allow(task.context_task).to receive(:read)

      allow(Context).to receive_message_chain('s3.pipeline_bucket_name')
      allow(Defaults).to receive_message_chain('sections').and_return(_get_sections)

      allow(FileUtils).to receive(:rm_rf)
      allow(AwsHelper).to receive(:s3_delete_objects)

      expect { task.context }.not_to raise_error
    end
  end

  context '.artefacts' do
    it 'calls context_task.read' do
      task = _get_task

      allow(task).to receive(:_env).and_return({})

      allow(task.context_task).to receive(:read)

      expect(task.context_task).to receive(:read).once
      expect { task.artefacts }.not_to raise_error
    end

    it 'returns on non-local-dev' do
      task = _get_task

      allow(task).to receive(:_env).and_return({})
      expect { task.artefacts }.not_to raise_error
    end

    it 'executes on local-dev' do
      task = _get_task

      allow(task).to receive(:_env).and_return({
        'local_dev' => true
      })

      allow(task.context_task).to receive(:read)

      allow(Context).to receive_message_chain('s3.artefact_bucket_name')
      allow(Defaults).to receive_message_chain('sections').and_return(_get_sections)

      allow(FileUtils).to receive(:rm_rf)
      allow(AwsHelper).to receive(:s3_delete_objects)

      expect { task.artefacts }.not_to raise_error
    end
  end
end
