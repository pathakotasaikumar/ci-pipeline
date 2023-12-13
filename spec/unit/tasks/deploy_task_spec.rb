$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib"))

require 'tasks/deploy_task.rb'
require 'tasks/teardown_task.rb'
require 'component'
require 'consumable'
require 'runner'
require 'util/archive'
require 'util/stat_helper'

RSpec.describe Action do
  def _get_task
    result = DeployTask.new

    allow(result.context_task).to receive(:read)

    result
  end

  def _get_sections
    {
      :ase => 'ase',
      :plan_key => 'plan-key'
    }
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

      expect(task.name).to eq("deploy")
    end
  end

  context '.check_state' do
    it 'calls context_task.read' do
      task = _get_task

      allow(task).to receive(:_env).and_return({})

      allow(task.context_task).to receive(:read)

      expect(task.context_task).to receive(:read).once
      expect { task.check_state }.not_to raise_error
    end

    it 'raises on non-start state' do
      task = _get_task

      allow(Context).to receive_message_chain('pipeline.state').and_return('failed')

      expect {
        task.check_state
      }.to raise_error(/Cannot perform deployment from current state/)
    end

    it 'works start state' do
      task = _get_task

      allow(Context).to receive_message_chain('pipeline.state').and_return('start')

      expect {
        task.check_state
      }.not_to raise_error
    end
  end

  context '.check_service_now' do
    it 'calls context_task.read' do
      task = _get_task

      allow(task).to receive(:_env).and_return({})

      allow(task.context_task).to receive(:read)

      expect(task.context_task).to receive(:read).once
      expect { task.check_service_now }.not_to raise_error
    end

    it 'checks servicenow' do
      task = _get_task

      allow(ServiceNow).to receive(:request_deploy)

      expect {
        task.check_service_now
      }.not_to raise_error
    end
  end

  context '.kms' do
    it 'calls context_task.read' do
      task = _get_task

      allow(Runner).to receive(:deploy_kms)
      allow(task).to receive(:_env).and_return({})

      allow(task.context_task).to receive(:read)

      expect(task.context_task).to receive(:read).once

      expect { task.kms }.not_to raise_error
    end

    it 'calls deploy_kms' do
      task = _get_task

      allow(Runner).to receive(:deploy_kms)

      expect {
        task.kms
      }.not_to raise_error
    end
  end

  context '.load_persistence' do
    it 'calls load_components' do
      task = _get_task

      allow(task).to receive(:load_components)

      allow(Runner).to receive(:load_persistence)
      expect(task).to receive(:load_components).once

      expect { task.load_persistence }.not_to raise_error
    end

    it 'calls load_persistence' do
      task = _get_task

      allow(task).to receive(:load_components)
      allow(Runner).to receive(:load_persistence)

      expect {
        task.load_persistence
      }.not_to raise_error
    end
  end

  context '.security' do
    it 'calls load_components' do
      task = _get_task

      allow(task).to receive(:load_components)

      allow(Runner).to receive(:deploy_security_items)
      expect(task).to receive(:load_components).once

      expect { task.security }.not_to raise_error
    end

    it 'calls security' do
      task = _get_task

      allow(task).to receive(:load_components)
      allow(Runner).to receive(:deploy_security_items)

      expect {
        task.security
      }.not_to raise_error
    end
  end

  context '.print_resource_group' do
    it 'calls print_resource_group' do
      task = _get_task

      allow(Defaults).to receive(:resource_group_url)

      expect {
        task.print_resource_group
      }.not_to raise_error
    end
  end

  context '.copy_artefacts' do
    it 'calls context_task.read' do
      task = _get_task

      allow(task).to receive(:_env).and_return({})
      allow(task.context_task).to receive(:read)

      allow(Context).to receive_message_chain('s3.artefact_bucket_name')
      task.instance_variable_set(:@components, _get_components)

      allow(AwsHelper).to receive(:s3_copy_object)

      expect(task.context_task).to receive(:read).once
      expect { task.copy_artefacts }.not_to raise_error
    end

    it 'copy_artefacts' do
      task = _get_task

      allow(Context).to receive_message_chain('s3.artefact_bucket_name')
      task.instance_variable_set(:@components, _get_components)

      allow(AwsHelper).to receive(:s3_copy_object)

      expect {
        task.copy_artefacts
      }.not_to raise_error
    end

    it 'raises on error' do
      task = _get_task

      allow(Context).to receive_message_chain('s3.artefact_bucket_name')
      task.instance_variable_set(:@components, _get_components)

      allow(AwsHelper).to receive(:s3_copy_object).and_raise('Cannot copy stuff')

      expect {
        task.copy_artefacts
      }.to raise_error(/Failed to copy build artefacts to deployment bucket/)
    end
  end

  context '.pre_deploy_actions' do
    it 'skips on skip_actions = true' do
      task = _get_task

      allow(Context).to receive_message_chain('environment.variable')
        .with('skip_actions', anything)
        .and_return('true')

      expect {
        task.pre_deploy_actions
      }.not_to raise_error
    end

    it 'runs PreDeploy actions' do
      task = _get_task

      allow(Context).to receive_message_chain('environment.variable')
        .with('skip_actions', anything)
        .and_return('false')

      allow(Runner).to receive_message_chain(:run_actions)
        .with(anything, 'PreDeploy')
        .and_return([[], []])

      expect {
        task.pre_deploy_actions
      }.not_to raise_error
    end

    it 'raises on failes PreDeploy actions' do
      task = _get_task

      allow(Context).to receive_message_chain('environment.variable')
        .with('skip_actions', anything)
        .and_return('false')

      allow(Runner).to receive_message_chain(:run_actions)
        .with(anything, 'PreDeploy')
        .and_return([[], _get_failed_components])

      allow(Log).to receive(:snow)

      expect {
        task.pre_deploy_actions
      }.to raise_error(/Failed to run user defined actions/)
    end
  end

  context '.post_deploy_actions' do
    it 'skips on skip_actions = true' do
      task = _get_task

      allow(Context).to receive_message_chain('environment.variable')
        .with('skip_actions', anything)
        .and_return('true')

      expect {
        task.post_deploy_actions
      }.not_to raise_error
    end

    it 'runs PostDeploy actions' do
      task = _get_task

      allow(Context).to receive_message_chain('environment.variable')
        .with('skip_actions', anything)
        .and_return('false')

      allow(Runner).to receive_message_chain(:run_actions)
        .with(anything, 'PostDeploy')
        .and_return([[], []])

      expect {
        task.post_deploy_actions
      }.not_to raise_error
    end

    it 'raises on failes PostDeploy actions' do
      task = _get_task

      allow(Context).to receive_message_chain('environment.variable')
        .with('skip_actions', anything)
        .and_return('false')

      allow(Runner).to receive_message_chain(:run_actions)
        .with(anything, 'PostDeploy')
        .and_return([[], _get_failed_components])

      allow(Log).to receive(:snow)

      expect {
        task.post_deploy_actions
      }.to raise_error(/Failed to run user defined actions/)
    end
  end

  context '.components' do
    it 'calls load_components' do
      task = _get_task

      allow(task).to receive(:load_components)

      allow(Runner).to receive(:deploy_security_items)
      expect(task).to receive(:load_components).once

      allow(Defaults).to receive(:sections).and_return(_get_sections)
      allow(Runner).to receive_message_chain(:deploy)
        .and_return([[], []])

      allow(Log).to receive(:snow)
      allow(Context).to receive_message_chain('pipeline.set_variables')

      expect {
        task.components
      }.not_to raise_error
    end

    it 'deploys components' do
      task = _get_task

      allow(task).to receive(:load_components)

      allow(Defaults).to receive(:sections).and_return(_get_sections)
      allow(Runner).to receive_message_chain(:deploy)
        .and_return([[], []])

      allow(Log).to receive(:snow)
      allow(Context).to receive_message_chain('pipeline.set_variables')

      expect {
        task.components
      }.not_to raise_error
    end

    it 'raises on failed components' do
      task = _get_task

      allow(task).to receive(:load_components)

      allow(Defaults).to receive(:sections).and_return(_get_sections)
      allow(Runner).to receive_message_chain(:deploy)
        .and_return([[], _get_failed_components])

      allow(Log).to receive(:snow)
      allow(Context).to receive_message_chain('pipeline.set_variables')

      expect {
        task.components
      }.to raise_error(/Failed to deploy components/)
    end
  end

  context '.load_components' do
    it 'calls context_task.read' do
      task = _get_task

      allow(task.context_task).to receive(:read)

      response = double(Object)

      allow(response).to receive(:metadata).and_return({
        'bamboo_plankey' => 'plan-key',
        'bamboo_buildnumber' => 'plan-buil-number'
      })

      allow(Context).to receive_message_chain('component.set_variables')
      allow(Context).to receive_message_chain('s3.artefact_bucket_name').and_return('pipeline-bucket')

      allow(Defaults).to receive(:sections).and_return(_get_sections)
      allow(Defaults).to receive(:ci_artefact_path).and_return('ci-path')
      allow(AwsHelper).to receive(:s3_download_object).and_return(response)

      allow(task).to receive(:untar)
      allow(task).to receive(:gunzip)

      allow(Component).to receive(:load_all).and_return([])
      allow(Consumable).to receive(:instantiate_all)

      allow(FileUtils).to receive(:rm_rf)

      expect {
        task.load_components
      }.not_to raise_error
    end

    it 'loads components' do
      task = _get_task

      allow(task.context_task).to receive(:read)

      response = double(Object)

      allow(response).to receive(:metadata).and_return({
        'bamboo_plankey' => 'plan-key',
        'bamboo_buildnumber' => 'plan-buil-number'
      })

      allow(Context).to receive_message_chain('component.set_variables')
      allow(Context).to receive_message_chain('s3.artefact_bucket_name').and_return('pipeline-bucket')

      allow(Defaults).to receive(:sections).and_return(_get_sections)
      allow(Defaults).to receive(:ci_artefact_path).and_return('ci-path')
      allow(AwsHelper).to receive(:s3_download_object).and_return(response)

      allow(task).to receive(:untar)
      allow(task).to receive(:gunzip)

      allow(Component).to receive(:load_all).and_return([])
      allow(Consumable).to receive(:instantiate_all)

      allow(FileUtils).to receive(:rm_rf)

      expect {
        task.load_components
      }.not_to raise_error
    end

    it 'loads components' do
      task = _get_task

      allow(task.context_task).to receive(:read)

      allow(Context).to receive_message_chain('s3.artefact_bucket_name').and_raise('Cannot load components')
      allow(FileUtils).to receive(:rm_rf)

      expect {
        task.load_components
      }.to raise_error(/Failed to load all components/)
    end
  end

  context '.deploy' do
    it 'deploys flow' do
      task = _get_task

      context_task = double(ContextTask)
      allow(context_task).to receive(:write)
      task.instance_variable_set(:@context_task, context_task)

      allow(Log).to receive(:snow)
      allow(Log).to receive(:splunk_http)

      allow(task).to receive(:check_state)
      allow(task).to receive(:check_service_now)

      allow(task).to receive(:load_components)
      allow(task).to receive(:copy_artefacts)
      allow(task).to receive(:print_resource_group)
      allow(task).to receive(:kms)
      allow(task).to receive(:load_persistence)
      allow(task).to receive(:security)
      allow(task).to receive(:pre_deploy_actions)
      allow(task).to receive(:components)
      allow(task).to receive(:post_deploy_actions)

      allow(Context).to receive_message_chain('pipeline.state=')
      allow(ServiceNow).to receive(:done_success)

      allow(StatHelper).to receive(:exceptions_stats)

      allow(StatHelper).to receive(:start_pipeline_stage)
      allow(StatHelper).to receive(:finish_pipeline_stage)

      expect {
        task.deploy
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
      allow(task).to receive(:copy_artefacts)
      allow(task).to receive(:print_resource_group)
      allow(task).to receive(:kms)
      allow(task).to receive(:load_persistence)
      allow(task).to receive(:security)
      allow(task).to receive(:pre_deploy_actions)
      allow(task).to receive(:components)
      allow(task).to receive(:post_deploy_actions)

      allow(Context).to receive_message_chain('pipeline.state=')
      allow(ServiceNow).to receive(:done_success)

      allow(StatHelper).to receive(:exceptions_stats)

      allow(StatHelper).to receive(:start_pipeline_stage).and_raise('cannot use splunk')
      allow(StatHelper).to receive(:finish_pipeline_stage)

      expect {
        task.deploy
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
      allow(task).to receive(:copy_artefacts)
      allow(task).to receive(:print_resource_group)
      allow(task).to receive(:kms)
      allow(task).to receive(:load_persistence)
      allow(task).to receive(:security)
      allow(task).to receive(:pre_deploy_actions)
      allow(task).to receive(:components)
      allow(task).to receive(:post_deploy_actions)

      allow(Context).to receive_message_chain('pipeline.state=')
      allow(ServiceNow).to receive(:done_success)

      allow(StatHelper).to receive(:exceptions_stats)

      allow(StatHelper).to receive(:start_pipeline_stage)
      allow(StatHelper).to receive(:finish_pipeline_stage).and_raise('cannot use splunk')

      expect {
        task.deploy
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
      allow(task).to receive(:copy_artefacts)
      allow(task).to receive(:print_resource_group)
      allow(task).to receive(:kms)
      allow(task).to receive(:load_persistence)
      allow(task).to receive(:security)
      allow(task).to receive(:pre_deploy_actions)
      allow(task).to receive(:components)
      allow(task).to receive(:post_deploy_actions)

      allow(Context).to receive_message_chain('pipeline.state=')
      allow(ServiceNow).to receive(:done_success)

      allow(StatHelper).to receive(:exceptions_stats)

      allow(StatHelper).to receive(:start_pipeline_stage)
      allow(StatHelper).to receive(:finish_pipeline_stage)

      expect {
        task.deploy
      }.not_to raise_error
    end

    it 'raises error on provision flow' do
      task = _get_task

      context_task = double(ContextTask)
      allow(context_task).to receive(:write)
      task.instance_variable_set(:@context_task, context_task)

      teardown_task = double(TeardownTask)
      allow(teardown_task).to receive(:components)
      task.instance_variable_set(:@teardown_task, teardown_task)

      allow(Log).to receive(:snow)
      allow(Log).to receive(:splunk_http)

      allow(task).to receive(:check_state)
      allow(task).to receive(:check_service_now)

      allow(task).to receive(:load_components).and_raise('cannot provision')
      allow(task).to receive(:copy_artefacts)
      allow(task).to receive(:print_resource_group)
      allow(task).to receive(:kms)
      allow(task).to receive(:load_persistence)
      allow(task).to receive(:security)
      allow(task).to receive(:pre_deploy_actions)
      allow(task).to receive(:components)
      allow(task).to receive(:post_deploy_actions)

      allow(Context).to receive_message_chain('pipeline.state=')
      allow(ServiceNow).to receive(:done_failure)

      allow(StatHelper).to receive(:exceptions_stats)

      allow(StatHelper).to receive(:start_pipeline_stage)
      allow(StatHelper).to receive(:finish_pipeline_stage)

      expect {
        task.deploy
      }.to raise_error(/cannot provision/)
    end

    it "cleans up on failure" do
      task = _get_task

      context_task = double(ContextTask)
      allow(context_task).to receive(:write).and_raise('cannot save context')
      task.instance_variable_set(:@context_task, context_task)

      allow(task).to receive(:_cleanup_after_deploy_failure?).and_return(true)

      teardown_task = double(TeardownTask)
      expect(teardown_task).to receive(:components)
      task.instance_variable_set(:@teardown_task, teardown_task)

      allow(Log).to receive(:snow)
      allow(Log).to receive(:error)
      allow(Log).to receive(:splunk_http)

      allow(task).to receive(:check_state)
      allow(task).to receive(:check_service_now)

      allow(task).to receive(:load_components).and_raise('cannot provision')
      allow(task).to receive(:copy_artefacts)
      allow(task).to receive(:print_resource_group)
      allow(task).to receive(:kms)
      allow(task).to receive(:load_persistence)
      allow(task).to receive(:security)
      allow(task).to receive(:pre_deploy_actions)
      allow(task).to receive(:components)
      allow(task).to receive(:post_deploy_actions)

      allow(Context).to receive_message_chain('pipeline.state=')
      allow(ServiceNow).to receive(:done_failure)

      allow(StatHelper).to receive(:exceptions_stats)

      allow(StatHelper).to receive(:start_pipeline_stage)
      allow(StatHelper).to receive(:finish_pipeline_stage)

      expect {
        task.deploy
      }.to raise_error(/cannot provision/)
    end

    it "skips cleans up on _cleanup_after_deploy_failure = false" do
      task = _get_task

      context_task = double(ContextTask)
      allow(context_task).to receive(:write).and_raise('cannot save context')
      task.instance_variable_set(:@context_task, context_task)

      allow(task).to receive(:_cleanup_after_deploy_failure?).and_return(nil)

      teardown_task = double(TeardownTask)
      expect(teardown_task).not_to receive(:components)
      task.instance_variable_set(:@teardown_task, teardown_task)

      allow(Log).to receive(:snow)
      allow(Log).to receive(:error)
      allow(Log).to receive(:splunk_http)

      allow(task).to receive(:check_state)
      allow(task).to receive(:check_service_now)

      allow(task).to receive(:load_components).and_raise('cannot provision')
      allow(task).to receive(:copy_artefacts)
      allow(task).to receive(:print_resource_group)
      allow(task).to receive(:kms)
      allow(task).to receive(:load_persistence)
      allow(task).to receive(:security)
      allow(task).to receive(:pre_deploy_actions)
      allow(task).to receive(:components)
      allow(task).to receive(:post_deploy_actions)

      allow(Context).to receive_message_chain('pipeline.state=')
      allow(ServiceNow).to receive(:done_failure)

      allow(StatHelper).to receive(:exceptions_stats)

      allow(StatHelper).to receive(:start_pipeline_stage)
      allow(StatHelper).to receive(:finish_pipeline_stage)

      expect {
        task.deploy
      }.to raise_error(/cannot provision/)
    end
  end

  context '._cleanup_after_release_failure?' do
    it 'returns values' do
      task = _get_task

      method_name     = :_cleanup_after_deploy_failure?
      bamboo_var_name = task.__send__(:_deploy_failure_cleanup_flag_name)

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

  context '._deploy_failure_cleanup_flag_name' do
    it 'returns value' do
      task = _get_task

      method_name     = :_cleanup_after_deploy_failure?
      bamboo_var_name = task.__send__(:_deploy_failure_cleanup_flag_name)

      expect(bamboo_var_name).to eq('bamboo_cleanup_after_deploy_failure')
    end
  end

  context '.deploy errors' do
    it 'should raise PipelineAggregateError on component error' do
      task = _get_task

      context_task = double(ContextTask)
      allow(context_task).to receive(:write)
      task.instance_variable_set(:@context_task, context_task)

      teardown_task = double(TeardownTask)
      allow(teardown_task).to receive(:components)
      task.instance_variable_set(:@teardown_task, teardown_task)

      allow(Log).to receive(:snow)
      allow(Log).to receive(:splunk_http)

      allow(task).to receive(:check_state)
      allow(task).to receive(:check_service_now)

      allow(task).to receive(:load_components)
      allow(task).to receive(:copy_artefacts)
      allow(task).to receive(:print_resource_group)
      allow(task).to receive(:kms)
      allow(task).to receive(:load_persistence)
      allow(task).to receive(:security)
      allow(task).to receive(:pre_deploy_actions)
      allow(task).to receive(:post_deploy_actions)

      allow(Context).to receive_message_chain('pipeline.state=')
      allow(Context).to receive_message_chain('pipeline.set_variables')

      allow(ServiceNow).to receive(:done_success)

      allow(StatHelper).to receive(:exceptions_stats)

      allow(StatHelper).to receive(:start_pipeline_stage)
      allow(StatHelper).to receive(:finish_pipeline_stage)

      allow(Runner).to receive(:deploy) .and_return([[], _get_failed_components])

      expect {
        task.deploy
      }.to raise_error(PipelineAggregateError, /Failed to deploy components:.+failed component.+/)
    end
  end
end
