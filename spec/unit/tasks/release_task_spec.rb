$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib"))

require 'tasks/release_task.rb'
require 'component'
require 'consumable'
require 'runner'
require 'util/archive'
require 'util/stat_helper'

RSpec.describe Action do
  def _get_task
    result = ReleaseTask.new

    context_task = double(ContextTask)
    allow(context_task).to receive(:read)
    result.instance_variable_set(:@context_task, context_task)

    result
  end

  def _get_components
    {
      'test-component' => {

      }
    }
  end

  def _get_failed_components
    component = double(Object)

    allow(component).to receive(:name).and_return('failed component')
    allow(component).to receive(:component_name).and_return('failed component')
    allow(component).to receive(:definition).and_return({})

    [
      component
    ]
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

      expect(task.name).to eq("release")
    end
  end

  context '.check_service_now' do
    it 'calls context_task.read' do
      task = _get_task

      allow(task).to receive(:_env).and_return({})

      allow(task.context_task).to receive(:read)
      expect(task.context_task).to receive(:read).once

      allow(ServiceNow).to receive(:request_release)

      expect { task.check_service_now }.not_to raise_error
    end

    it 'check service now' do
      task = _get_task

      allow(ServiceNow).to receive(:request_release)

      expect { task.check_service_now }.not_to raise_error
    end
  end

  context '.load_components' do
    it 'calls context_task.read' do
      task = _get_task

      allow(task).to receive(:_env).and_return({})

      allow(task.context_task).to receive(:read)
      expect(task.context_task).to receive(:read).once

      allow(Context).to receive_message_chain('pipeline.variable')
      allow(Consumable).to receive(:instantiate_all)

      expect { task.load_components }.not_to raise_error
    end

    it 'loads components' do
      task = _get_task

      allow(Context).to receive_message_chain('pipeline.variable')
      allow(Consumable).to receive(:instantiate_all)

      expect { task.load_components }.not_to raise_error
    end
  end

  context '.components' do
    it 'calls load_components' do
      task = _get_task

      allow(task).to receive(:load_components)

      allow(Runner).to receive(:load_persistence)
      expect(task).to receive(:load_components).once

      allow(Context).to receive_message_chain('pipeline.set_variables')
      allow(Runner).to receive(:release).and_return([_get_failed_components, []])

      expect { task.components }.not_to raise_error
    end

    it 'releases components' do
      task = _get_task

      allow(task).to receive(:load_components)

      allow(Context).to receive_message_chain('pipeline.set_variables')
      allow(Runner).to receive(:release).and_return([_get_failed_components, []])

      expect { task.components }.not_to raise_error
    end

    it 'raises on failed components' do
      task = _get_task

      allow(task).to receive(:load_components)

      allow(Context).to receive_message_chain('pipeline.set_variables')
      allow(Runner).to receive(:release).and_return([[], _get_failed_components])

      expect { task.components }.to raise_error(/Failed to release components/)
    end
  end

  context '.pre_release_actions' do
    it 'skips on skip_actions = true' do
      task = _get_task

      allow(Context).to receive_message_chain('environment.variable')
        .with('skip_actions', anything)
        .and_return('true')

      allow(Context).to receive_message_chain('environment.variable')
        .with('skip_release', anything)
        .and_return('true')

      expect {
        task.pre_release_actions
      }.not_to raise_error
    end

    it 'skips on skip_release = true' do
      task = _get_task

      allow(Context).to receive_message_chain('environment.variable')
        .with('skip_actions', anything)
        .and_return('false')

      allow(Context).to receive_message_chain('environment.variable')
        .with('skip_release', anything)
        .and_return('true')

      expect {
        task.pre_release_actions
      }.not_to raise_error
    end

    it 'runs PreRelease actions' do
      task = _get_task

      allow(Context).to receive_message_chain('environment.variable')
        .with('skip_actions', anything)
        .and_return('false')

      allow(Context).to receive_message_chain('environment.variable')
        .with('skip_release', anything)
        .and_return('false')

      allow(Runner).to receive(:run_actions)
        .with(anything, 'PreRelease')
        .and_return([[], []])

      expect {
        task.pre_release_actions
      }.not_to raise_error
    end

    it 'raises on failes PreRelease actions' do
      task = _get_task

      allow(Context).to receive_message_chain('environment.variable')
        .with('skip_actions', anything)
        .and_return('false')

      allow(Context).to receive_message_chain('environment.variable')
        .with('skip_release', anything)
        .and_return('false')

      allow(Runner).to receive(:run_actions)
        .with(anything, 'PreRelease')
        .and_return([[], _get_failed_components])

      allow(Log).to receive(:snow)

      expect {
        task.pre_release_actions
      }.to raise_error(/Failed to run user defined actions/)
    end
  end

  context '.post_release_actions' do
    it 'skips on skip_actions = true' do
      task = _get_task

      allow(Context).to receive_message_chain('environment.variable')
        .with('skip_actions', anything)
        .and_return('true')

      allow(Context).to receive_message_chain('environment.variable')
        .with('skip_release', anything)
        .and_return('true')

      expect {
        task.post_release_actions
      }.not_to raise_error
    end

    it 'skips on skip_release = true' do
      task = _get_task

      allow(Context).to receive_message_chain('environment.variable')
        .with('skip_actions', anything)
        .and_return('false')

      allow(Context).to receive_message_chain('environment.variable')
        .with('skip_release', anything)
        .and_return('true')

      expect {
        task.post_release_actions
      }.not_to raise_error
    end

    it 'runs PostRelease actions' do
      task = _get_task

      allow(Context).to receive_message_chain('environment.variable')
        .with('skip_actions', anything)
        .and_return('false')

      allow(Context).to receive_message_chain('environment.variable')
        .with('skip_release', anything)
        .and_return('false')

      allow(Runner).to receive(:run_actions)
        .with(anything, 'PostRelease')
        .and_return([[], []])

      expect {
        task.post_release_actions
      }.not_to raise_error
    end

    it 'raises on failes PostRelease actions' do
      task = _get_task

      allow(Context).to receive_message_chain('environment.variable')
        .with('skip_actions', anything)
        .and_return('false')

      allow(Context).to receive_message_chain('environment.variable')
        .with('skip_release', anything)
        .and_return('false')

      allow(Runner).to receive(:run_actions)
        .with(anything, 'PostRelease')
        .and_return([[], _get_failed_components])

      allow(Log).to receive(:snow)

      expect {
        task.post_release_actions
      }.to raise_error(/Failed to run user defined actions/)
    end
  end

  context '.check_state' do
    it 'calls context_task.read' do
      task = _get_task

      allow(task).to receive(:_env).and_return({})

      allow(task.context_task).to receive(:read)
      expect(task.context_task).to receive(:read).once

      allow(Context).to receive_message_chain('pipeline.state')
        .and_return("deployed")

      expect { task.check_state }.not_to raise_error
    end

    it 'checks state' do
      task = _get_task

      states = ["deployed", "released", "release_failed"]

      states.each do |state|
        allow(Context).to receive_message_chain('pipeline.state')
          .and_return(state)

        expect { task.check_state }.not_to raise_error
      end
    end

    it 'raises on incorrect state' do
      task = _get_task

      states = ["deployed1", "released2", "release_failed3"]

      states.each do |state|
        allow(Context).to receive_message_chain('pipeline.state')
          .and_return(state)

        expect { task.check_state }.to raise_error(/Cannot perform release from current state/)
      end
    end
  end

  context 'release' do
    it 'releases flow' do
      task = _get_task

      context_task = double(ContextTask)
      allow(context_task).to receive(:write)
      task.instance_variable_set(:@context_task, context_task)

      allow(Log).to receive(:snow)
      allow(Log).to receive(:splunk_http)

      allow(task).to receive(:check_state)
      allow(task).to receive(:check_service_now)

      allow(task).to receive(:load_components)
      allow(task).to receive(:pre_release_actions)
      allow(task).to receive(:components)
      allow(task).to receive(:post_release_actions)

      allow(Context).to receive_message_chain('pipeline.state=')
      allow(ServiceNow).to receive(:done_success)

      allow(StatHelper).to receive(:exceptions_stats)

      allow(StatHelper).to receive(:start_pipeline_stage)
      allow(StatHelper).to receive(:finish_pipeline_stage)

      expect {
        task.release
      }.not_to raise_error
    end

    it 'does not raise on start_pipeline_stage error' do
      task = _get_task

      context_task = double(ContextTask)
      allow(context_task).to receive(:write)
      task.instance_variable_set(:@context_task, context_task)

      allow(Log).to receive(:snow)
      allow(Log).to receive(:splunk_http)

      allow(task).to receive(:check_state)
      allow(task).to receive(:check_service_now)

      allow(task).to receive(:load_components)
      allow(task).to receive(:pre_release_actions)
      allow(task).to receive(:components)
      allow(task).to receive(:post_release_actions)

      allow(Context).to receive_message_chain('pipeline.state=')
      allow(ServiceNow).to receive(:done_success)

      allow(StatHelper).to receive(:exceptions_stats)

      allow(StatHelper).to receive(:start_pipeline_stage).and_raise('cannot use splunk')
      allow(StatHelper).to receive(:finish_pipeline_stage)

      expect {
        task.release
      }.not_to raise_error
    end

    it 'does not raise on finish_pipeline_stage error' do
      task = _get_task

      context_task = double(ContextTask)
      allow(context_task).to receive(:write)
      task.instance_variable_set(:@context_task, context_task)

      allow(Log).to receive(:snow)
      allow(Log).to receive(:splunk_http)

      allow(task).to receive(:check_state)
      allow(task).to receive(:check_service_now)

      allow(task).to receive(:load_components)
      allow(task).to receive(:pre_release_actions)
      allow(task).to receive(:components)
      allow(task).to receive(:post_release_actions)

      allow(Context).to receive_message_chain('pipeline.state=')
      allow(ServiceNow).to receive(:done_success)

      allow(StatHelper).to receive(:exceptions_stats)

      allow(StatHelper).to receive(:start_pipeline_stage)
      allow(StatHelper).to receive(:finish_pipeline_stage).and_raise('cannot use splunk')

      expect {
        task.release
      }.not_to raise_error
    end

    it 'does not raise on context save error' do
      task = _get_task

      context_task = double(ContextTask)
      allow(context_task).to receive(:write).and_raise('cannot save context')
      task.instance_variable_set(:@context_task, context_task)

      allow(Log).to receive(:snow)
      allow(Log).to receive(:splunk_http)

      allow(task).to receive(:check_state)
      allow(task).to receive(:check_service_now)

      allow(task).to receive(:load_components)
      allow(task).to receive(:pre_release_actions)
      allow(task).to receive(:components)
      allow(task).to receive(:post_release_actions)

      allow(Context).to receive_message_chain('pipeline.state=')
      allow(ServiceNow).to receive(:done_success)

      allow(StatHelper).to receive(:exceptions_stats)

      allow(StatHelper).to receive(:start_pipeline_stage)
      allow(StatHelper).to receive(:finish_pipeline_stage)

      expect {
        task.release
      }.not_to raise_error
    end

    it 'raises error on provision flow' do
      task = _get_task

      context_task = double(ContextTask)
      allow(context_task).to receive(:write)
      task.instance_variable_set(:@context_task, context_task)

      allow(Log).to receive(:snow)
      allow(Log).to receive(:splunk_http)

      allow(task).to receive(:check_state)
      allow(task).to receive(:check_service_now)

      allow(task).to receive(:load_components).and_raise('cannot provision')
      allow(task).to receive(:pre_release_actions)
      allow(task).to receive(:components)
      allow(task).to receive(:post_release_actions)

      allow(Context).to receive_message_chain('pipeline.state=')
      allow(ServiceNow).to receive(:done_success)

      allow(StatHelper).to receive(:exceptions_stats)

      allow(StatHelper).to receive(:start_pipeline_stage)
      allow(StatHelper).to receive(:finish_pipeline_stage)

      expect {
        task.release
      }.to raise_error(/cannot provision/)
    end

    it 'cleans up on error and bamboo_cleanup_after_release_failure = true' do
      task = _get_task

      context_task = double(ContextTask)
      allow(context_task).to receive(:write)
      task.instance_variable_set(:@context_task, context_task)

      teardown_task = double(TeardownTask)
      expect(teardown_task).to receive(:components)
      task.instance_variable_set(:@teardown_task, teardown_task)

      allow(task).to receive(:_cleanup_after_release_failure?).and_return(true)

      allow(Log).to receive(:snow)
      allow(Log).to receive(:splunk_http)

      allow(task).to receive(:check_state)
      allow(task).to receive(:check_service_now)

      allow(task).to receive(:load_components).and_raise('cannot provision')
      allow(task).to receive(:pre_release_actions)
      allow(task).to receive(:components)
      allow(task).to receive(:post_release_actions)

      allow(Context).to receive_message_chain('pipeline.state=')
      allow(ServiceNow).to receive(:done_success)

      allow(StatHelper).to receive(:exceptions_stats)

      allow(StatHelper).to receive(:start_pipeline_stage)
      allow(StatHelper).to receive(:finish_pipeline_stage)

      expect {
        task.release
      }.to raise_error(/cannot provision/)
    end

    it 'skips cleanup on error and bamboo_cleanup_after_release_failure = false' do
      task = _get_task

      context_task = double(ContextTask)
      allow(context_task).to receive(:write)
      task.instance_variable_set(:@context_task, context_task)

      teardown_task = double(TeardownTask)
      expect(teardown_task).not_to receive(:components)
      task.instance_variable_set(:@teardown_task, teardown_task)

      allow(task).to receive(:_cleanup_after_release_failure?).and_return(nil)

      allow(Log).to receive(:snow)
      allow(Log).to receive(:splunk_http)

      allow(task).to receive(:check_state)
      allow(task).to receive(:check_service_now)

      allow(task).to receive(:load_components).and_raise('cannot provision')
      allow(task).to receive(:pre_release_actions)
      allow(task).to receive(:components)
      allow(task).to receive(:post_release_actions)

      allow(Context).to receive_message_chain('pipeline.state=')
      allow(ServiceNow).to receive(:done_success)

      allow(StatHelper).to receive(:exceptions_stats)

      allow(StatHelper).to receive(:start_pipeline_stage)
      allow(StatHelper).to receive(:finish_pipeline_stage)

      expect {
        task.release
      }.to raise_error(/cannot provision/)
    end
  end

  context '._cleanup_after_release_failure?' do
    it 'returns values' do
      task = _get_task

      method_name     = :_cleanup_after_release_failure?
      bamboo_var_name = "bamboo_cleanup_after_release_failure"

      # false by default
      allow(task).to receive(:_env).and_return({})
      expect(task.__send__(method_name)).to eq(false)

      # false from false or 'false'
      allow(task).to receive(:_env).and_return({ bamboo_var_name => false })
      expect(task.__send__(method_name)).to eq(false)

      allow(task).to receive(:_env).and_return({ bamboo_var_name => 'false' })
      expect(task.__send__(method_name)).to eq(false)

      # true from true or 'true'
      allow(task).to receive(:_env).and_return({ bamboo_var_name => true })
      expect(task.__send__(method_name)).to eq(true)

      allow(task).to receive(:_env).and_return({ bamboo_var_name => 'true' })
      expect(task.__send__(method_name)).to eq(true)

      # false for other values
      allow(task).to receive(:_env).and_return({ bamboo_var_name => 1 })
      expect(task.__send__(method_name)).to eq(false)

      allow(task).to receive(:_env).and_return({ bamboo_var_name => '1' })
      expect(task.__send__(method_name)).to eq(false)

      allow(task).to receive(:_env).and_return({ bamboo_var_name => nil })
      expect(task.__send__(method_name)).to eq(false)
    end
  end

  context '._release_failure_cleanup_flag_name' do
    it 'returns value' do
      task = _get_task

      method_name     = :_cleanup_after_deploy_failure?
      bamboo_var_name = task.__send__(:_release_failure_cleanup_flag_name)

      expect(bamboo_var_name).to eq('bamboo_cleanup_after_release_failure')
    end
  end

  context '.release errors' do
    it 'should raise PipelineAggregateError on component error' do
      task = _get_task

      context_task = double(ContextTask)
      allow(context_task).to receive(:write)
      task.instance_variable_set(:@context_task, context_task)

      teardown_task = double(TeardownTask)
      expect(teardown_task).to receive(:components)
      task.instance_variable_set(:@teardown_task, teardown_task)

      allow(task).to receive(:_cleanup_after_release_failure?).and_return(true)

      allow(Log).to receive(:snow)
      allow(Log).to receive(:splunk_http)

      allow(task).to receive(:check_state)
      allow(task).to receive(:check_service_now)

      allow(task).to receive(:load_components)
      allow(task).to receive(:pre_release_actions)
      allow(task).to receive(:post_release_actions)

      allow(Context).to receive_message_chain('pipeline.state=')
      allow(Context).to receive_message_chain('pipeline.set_variables')
      allow(ServiceNow).to receive(:done_success)

      allow(StatHelper).to receive(:exceptions_stats)

      allow(StatHelper).to receive(:start_pipeline_stage)
      allow(StatHelper).to receive(:finish_pipeline_stage)

      allow(Runner).to receive(:release) .and_return([[], _get_failed_components])

      expect {
        task.release
      }.to raise_error(PipelineAggregateError, /Failed to release components:.+failed component.+/)
    end
  end
end
