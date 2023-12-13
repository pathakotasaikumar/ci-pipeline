$LOAD_PATH.unshift("#{BASE_DIR}/lib")
require 'runner'

RSpec.describe Runner do
  before(:context) do
    @payload_dir = "#{TEST_DATA_DIR}/ciw-3/app/platform"

    @components = Component.load_all(@payload_dir, Defaults.sections[:ase].upcase, Defaults.sections[:branch])
    @consumables = Consumable.instantiate_all(@components)
  end

  def _configure_core_component(component)
    allow(component).to receive(:name_records).and_return([])
    allow(component).to receive(:stage).and_return("1")
    allow(component).to receive(:finalise_security_rules)
  end

  def _configure_component(component)
    _configure_core_component(component)
    allow(component).to receive(:pre_deploy)
    allow(component).to receive(:deploy)
    allow(component).to receive(:post_deploy)
    allow(component).to receive(:update_active_build?)
  end

  def _configure_failing_component(component)
    _configure_core_component(component)
    allow(component).to receive(:pre_deploy)
    allow(component).to receive(:deploy).and_raise('cannot deploy component')
    allow(component).to receive(:post_deploy)
    allow(component).to receive(:update_active_build?)
  end

  context '._require_released_build_number' do
    it 'raises on codedeploy mode and empty released_build_number' do
      allow(Defaults).to receive(:_deployment_mode).and_return('code_deploy')
      allow(Context).to receive_message_chain('persist.released_build_number').and_return(nil)

      expect {
        Runner.send(:_require_released_build_number)
      }.to raise_error(/CodeDeploy provision mode requires released build./)
    end

    it 'does not raise on non-codedeploy mode and empty released_build_number' do
      allow(Defaults).to receive(:_deployment_mode).and_return('code_deploy1')
      allow(Context).to receive_message_chain('persist.released_build_number').and_return(nil)

      expect {
        Runner.send(:_require_released_build_number)
      }.not_to raise_error
    end
  end

  context '._deployment_mode' do
    it 'returns value' do
      ENV['bamboo_deploy_mode'] = 'mode1'
      expect(Defaults.send(:_deployment_mode)).to eq('mode1')

      ENV['bamboo_deploy_mode'] = nil
      expect(Defaults.send(:_deployment_mode)).to eq(nil)
    end
  end

  context '._is_codedeploy_component?' do
    it 'returns true' do
      component = double(Object)

      allow(component).to receive_message_chain('class.to_s').and_return('Consumable')
      expect(Runner.__send__(:_is_codedeploy_component?, :component => component)).to eq(false)

      allow(component).to receive_message_chain('class.to_s').and_return('AwsCodeDeploy')
      expect(Runner.__send__(:_is_codedeploy_component?, :component => component)).to eq(true)
    end
  end

  context '._is_codedeploy_deployment_mode?' do
    it 'returns value' do
      allow(Defaults).to receive(:_deployment_mode).and_return('1')
      expect(Runner.send(:_is_codedeploy_deployment_mode?)).to eq(false)

      allow(Defaults).to receive(:_deployment_mode).and_return(nil)
      expect(Runner.send(:_is_codedeploy_deployment_mode?)).to eq(false)

      allow(Defaults).to receive(:_deployment_mode).and_return('code_deploy')
      expect(Runner.send(:_is_codedeploy_deployment_mode?)).to eq(true)
    end
  end

  context '.poll time' do
    it 'returns default poll time' do
      expect(Runner.run_actions_poll_time).to eq(5)
      expect(Runner.deploy_security_items_poll_time).to eq(5)

      expect(Runner.deploy_poll_time).to eq(5)
      expect(Runner.release_poll_time).to eq(5)
      expect(Runner.teardown_poll_time).to eq(10)
    end
  end

  context '.load_persistence' do
    it 'loads peristence for each component' do
      allow(Context).to receive(:component).and_call_original
      allow(Log).to receive(:info).and_call_original

      allow(Context).to receive_message_chain("persist.released_build_number") .and_return("5")
      allow(Context).to receive_message_chain("component.stack_id").with('my-webtier', "5") .and_return("my-webtier-stack-123")
      allow(Context).to receive_message_chain("component.build_number").with('my-webtier', "5") .and_return("5")

      expect(Log).to receive(:output).with("The currently released build is build 5")
      expect(Log).to receive(:output).with("Component \"my-webtier\" will be persisted from build 5")

      Runner.load_persistence(@consumables)
    end

    it 'does nothing on non-persistance build' do
      allow(Context).to receive_message_chain("persist.released_build_number").and_return(nil)
      Runner.load_persistence(@consumables)
    end
  end

  context '.deploy_kms' do
    it 'deploys kms' do
      allow(PipelineKmsKey).to receive(:deploy)

      Runner.deploy_kms
    end
  end

  context '.run_actions' do
    it 'runs actions' do
      components = double(Object)

      action1 = double(Action)
      consumable = double(Consumable)

      allow(action1).to receive(:step).and_return('Step1')
      allow(action1).to receive(:stage).and_return('PreRelease')
      allow(action1).to receive(:component).and_return(consumable)
      allow(action1).to receive(:invoke)

      allow(consumable).to receive(:component_name).and_return('my-component')
      allow(consumable).to receive(:actions).and_return([action1])

      allow(components).to receive(:values).and_return([consumable])
      allow(Runner).to receive(:run_actions_poll_time).and_return(0)

      successful_actions, failed_actions = Runner.run_actions(components, 'PreRelease')

      expect(successful_actions.count).to eq(1)
      expect(failed_actions.count).to eq(0)
    end

    it 'raises on failed action' do
      components = double(Object)

      action1 = double(Action)
      consumable = double(Consumable)

      allow(action1).to receive(:step).and_return('Step1')
      allow(action1).to receive(:stage).and_return('PreRelease')
      allow(action1).to receive(:component).and_return(consumable)
      allow(action1).to receive(:invoke).and_raise('Error running custom action on step1')

      allow(consumable).to receive(:component_name).and_return('my-component')
      allow(consumable).to receive(:actions).and_return([action1])

      allow(components).to receive(:values).and_return([consumable])
      allow(Runner).to receive(:run_actions_poll_time).and_return(0)

      successful_actions, failed_actions = Runner.run_actions(components, 'PreRelease')

      expect(successful_actions.count).to eq(0)
      expect(failed_actions.count).to eq(1)
    end
  end

  context '.deploy_security_items' do
    it 'deploys security items' do
      component = double(Object)

      allow(AsirSecurity).to receive(:deploy_security_items)
      allow(AsirSecurity).to receive(:deploy_security_rules)

      allow(Context).to receive_message_chain('asir.set_name=')

      allow(component).to receive(:definition).and_return({
        'AsirSet' => nil
      })

      allow(Runner).to receive(:deploy_security_items_poll_time).and_return(0)

      allow(component).to receive(:deploy_security_items)

      components = {
        'my-component' => component
      }

      Runner.deploy_security_items(components)
    end

    it 'raises on failed component security items' do
      component = double(Object)

      allow(AsirSecurity).to receive(:deploy_security_items)
      allow(AsirSecurity).to receive(:deploy_security_rules)

      allow(Context).to receive_message_chain('asir.set_name=')

      allow(component).to receive(:definition).and_return({
        'AsirSet' => nil
      })

      allow(Runner).to receive(:deploy_security_items_poll_time).and_return(0)
      allow(component).to receive(:deploy_security_items).and_raise("Cannot deploy security rules")

      components = {
        'my-component' => component
      }
      expect {
        Runner.deploy_security_items(components)
      }.to raise_error(/Failed to deploy security items for components/)
    end

    it 'does not fail on failed AsirSecurity security rules' do
      component = double(Object)

      allow(AsirSecurity).to receive(:deploy_security_items)
      allow(AsirSecurity).to receive(:deploy_security_rules).and_raise("Cannot deploy ASIR security rules")

      allow(Context).to receive_message_chain('asir.set_name=')

      allow(component).to receive(:definition).and_return({
        'AsirSet' => nil
      })

      allow(Runner).to receive(:deploy_security_items_poll_time).and_return(0)
      allow(component).to receive(:deploy_security_items)

      components = {
        'my-component' => component
      }
      expect {
        Runner.deploy_security_items(components)
      }.not_to raise_error
    end

    it 'raises on failed AsirSecurity security items' do
      component = double(Object)

      allow(AsirSecurity).to receive(:deploy_security_items).and_raise("Cannot deploy ASIR security items")
      allow(AsirSecurity).to receive(:deploy_security_rules)

      allow(Context).to receive_message_chain('asir.set_name=')

      allow(component).to receive(:definition).and_return({
        'AsirSet' => nil
      })

      allow(Runner).to receive(:deploy_security_items_poll_time).and_return(0)
      allow(component).to receive(:deploy_security_items)

      components = {
        'my-component' => component
      }
      expect {
        Runner.deploy_security_items(components)
      }.to raise_error(/Cannot deploy ASIR security items/)
    end
  end

  context '.deploy_r53_release_stack' do
    it 'creates new stack' do
      allow(Defaults).to receive(:dns_stack_name)
      allow(AwsHelper).to receive(:cfn_stack_exists).and_return(nil)

      allow(Defaults).to receive(:get_tags)
      allow(AwsHelper).to receive(:cfn_create_stack)

      Runner.deploy_r53_release_stack(template: { 'Resources' => {} })
    end

    it 'raise on new stack error' do
      allow(Defaults).to receive(:dns_stack_name)
      allow(AwsHelper).to receive(:cfn_stack_exists).and_return(nil)

      allow(AwsHelper).to receive(:cfn_create_stack).and_raise('Cannot create stack')

      expect {
        Runner.deploy_r53_release_stack(template: { 'Resources' => {} })
      }.to raise_error(/Cannot create stack/)
    end

    it 'updates new stack' do
      allow(Defaults).to receive(:dns_stack_name)
      allow(AwsHelper).to receive(:cfn_stack_exists).and_return(1)

      allow(AwsHelper).to receive(:cfn_update_stack)

      Runner.deploy_r53_release_stack(template: { 'Resources' => {} })
    end

    it 'raise on update stack error' do
      allow(Defaults).to receive(:dns_stack_name)
      allow(AwsHelper).to receive(:cfn_stack_exists).and_return(1)

      allow(AwsHelper).to receive(:cfn_update_stack).and_raise('Cannot update stack')

      expect {
        Runner.deploy_r53_release_stack(template: { 'Resources' => {} })
      }.to raise_error(/Cannot update stack/)
    end
  end

  context 'deploy_security_items with codedeploy' do
    it 'does not deploy on codedeploy mode' do
      allow(Runner).to receive(:_is_codedeploy_deployment_mode?).and_return(true)
      expect {
        Runner.deploy_security_items({})
      }.not_to raise_error
    end
  end

  context '.run_actions with codedeploy' do
    it 'does not deploy on codedeploy mode' do
      allow(Runner).to receive(:_is_codedeploy_deployment_mode?).and_return(true)
      expect {
        Runner.run_actions({}, "some stage")
      }.not_to raise_error
    end
  end

  context '._deploy_security_items?' do
    it 'returns true' do
      allow(Runner).to receive(:_is_codedeploy_deployment_mode?).and_return(false)
      expect(Runner.send(:_deploy_security_items?)).to eq(true)
    end

    it 'returns false for CodeDeploy' do
      allow(Runner).to receive(:_is_codedeploy_deployment_mode?).and_return(true)
      expect(Runner.send(:_deploy_security_items?)).to eq(false)
    end
  end

  context '._run_actions?' do
    it 'returns true' do
      allow(Runner).to receive(:_is_codedeploy_deployment_mode?).and_return(false)
      expect(Runner.send(:_run_actions?)).to eq(true)
    end

    it 'returns false for CodeDeploy' do
      allow(Runner).to receive(:_is_codedeploy_deployment_mode?).and_return(true)
      expect(Runner.send(:_run_actions?)).to eq(false)
    end
  end

  context '.deploy codedeploy mode' do
    it 'does not deploy non-codedeploy components' do
      component1 = double(Consumable)
      component2 = double(Consumable)

      allow(component1).to receive(:name_records).and_return([])
      allow(component2).to receive(:name_records).and_return([])

      allow(Context).to receive_message_chain('component.build_number')
      allow(Context).to receive_message_chain('persist.released_build_number').and_return(5)

      _configure_component(component1)
      _configure_component(component2)

      components = {
        "component1" => component1,
        "component2" => component2
      }

      allow(Defaults).to receive(:sections).and_return({
        :build => 1
      })

      allow(ServiceNow).to receive(:create_ci)
      allow(Runner).to receive(:deploy_poll_time).and_return(0)

      allow(Defaults).to receive(:_deployment_mode).and_return('code_deploy')
      allow(Runner).to receive(:_is_codedeploy_deployment_mode?).and_return(true)

      allow(Context).to receive_message_chain('component.set_variables')
      allow(Context).to receive_message_chain('persist.add_active_build')

      successful_components, failed_components = Runner.deploy(components)

      expect(successful_components.count).to eq(0)
      expect(failed_components.count).to eq(0)
    end

    it 'deploys codedeploy components' do
      component1 = double(Consumable)
      component2 = double(Consumable)

      allow(component2).to receive_message_chain('class.to_s').and_return("AwsCodeDeploy")

      allow(component1).to receive(:name_records).and_return([])
      allow(component2).to receive(:name_records).and_return([])

      allow(Context).to receive_message_chain('component.build_number')
      allow(Context).to receive_message_chain('persist.released_build_number').and_return(5)

      _configure_component(component1)
      _configure_component(component2)

      components = {
        "component1" => component1,
        "component2" => component2
      }

      allow(Defaults).to receive(:sections).and_return({
        :build => 1
      })

      allow(ServiceNow).to receive(:create_ci)
      allow(Runner).to receive(:deploy_poll_time).and_return(0)

      allow(Defaults).to receive(:_deployment_mode).and_return('code_deploy')
      allow(Runner).to receive(:_is_codedeploy_deployment_mode?).and_return(true)

      allow(Context).to receive_message_chain('component.set_variables')
      allow(Context).to receive_message_chain('persist.add_active_build')

      successful_components, failed_components = Runner.deploy(components)

      expect(successful_components.count).to eq(1)
      expect(failed_components.count).to eq(0)
    end
  end

  context '.deploy' do
    it 'deploys components' do
      component1 = double(Consumable)
      component2 = double(Consumable)

      _configure_component(component1)
      _configure_component(component2)

      components = {
        "component1" => component1,
        "component2" => component2
      }

      allow(Defaults).to receive(:sections).and_return({
        :build => 1
      })

      allow(PipelineMetadataService).to receive(:save_metadata)

      allow(ServiceNow).to receive(:create_ci)
      allow(Runner).to receive(:deploy_poll_time).and_return(0)

      successful_components, failed_components = Runner.deploy(components)

      expect(successful_components.count).to eq(2)
      expect(failed_components.count).to eq(0)
    end

    it 'deploys persisted components' do
      component1 = double(Consumable)
      component2 = double(Consumable)

      _configure_component(component1)
      _configure_component(component2)

      components = {
        "component1" => component1,
        "component2" => component2
      }

      # one of the components is persisted
      allow(Context).to receive_message_chain('component.build_number')
        .with('component1')
        .and_return('1')

      allow(Context).to receive_message_chain('component.build_number')
        .with('component2')
        .and_return(nil)

      allow(Defaults).to receive(:sections).and_return({
        :build => 1
      })

      allow(Context).to receive_message_chain('component.set_variables')
      allow(Context).to receive_message_chain('persist.add_active_build')

      allow(Runner).to receive(:deploy_poll_time).and_return(0)
      allow(ServiceNow).to receive(:create_ci)

      successful_components, failed_components = Runner.deploy(components)

      expect(successful_components.count).to eq(2)
      expect(failed_components.count).to eq(0)
    end
  end

  context '.release' do
    def _configure_release_component(component)
      allow(component).to receive(:name_records).and_return([])
      allow(component).to receive(:stage).and_return("1")
      allow(component).to receive(:pre_release).and_return(nil)
      allow(component).to receive(:release)
      allow(component).to receive(:post_release).and_return(nil)
      allow(component).to receive(:finalise_security_rules)
    end

    it 'releases components' do
      component1 = double(Consumable)
      component2 = double(Consumable)

      _configure_release_component(component1)
      _configure_release_component(component2)

      components = {
        "component1" => component1,
        "component2" => component2
      }

      allow(Defaults).to receive(:sections).and_return({
        :build => 1
      })

      allow(PipelineMetadataService).to receive(:save_metadata)

      allow(Runner).to receive(:release_poll_time).and_return(0)
      allow(ServiceNow).to receive(:create_ci)

      successful_components, failed_components = Runner.release(components)

      expect(successful_components.count).to eq(2)
      expect(failed_components.count).to eq(0)
    end

    it 'skips release with skip_release' do
      allow(Context).to receive_message_chain('persist.released_build_number')
        .and_return(1)

      allow(Context).to receive_message_chain('environment.variable')
        .with('skip_release', 'false')
        .and_return('true')

      allow(Runner).to receive(:release_poll_time).and_return(0)

      components = {}
      successful_components, failed_components = Runner.release(components)

      expect(successful_components.count).to eq(0)
      expect(failed_components.count).to eq(0)
    end

    it 'releases with process_release_r53_dns_record' do
      component1 = double(Consumable)
      component2 = double(Consumable)

      _configure_release_component(component1)
      _configure_release_component(component2)

      allow(component1).to receive(:process_release_r53_dns_record)
      allow(Runner).to receive(:deploy_r53_release_stack)

      allow(Defaults).to receive(:ad_dns_zone?)
        .and_return(nil)

      components = {
        "component1" => component1,
        "component2" => component2
      }

      allow(Defaults).to receive(:sections).and_return({
        :build => 1
      })

      allow(PipelineMetadataService).to receive(:save_metadata)

      allow(Runner).to receive(:release_poll_time).and_return(0)
      allow(ServiceNow).to receive(:create_ci)

      successful_components, failed_components = Runner.release(components)

      expect(successful_components.count).to eq(2)
      expect(failed_components.count).to eq(0)
    end

    it 'releases with process_release_r53_dns_record' do
      component1 = double(Consumable)
      component2 = double(Consumable)

      _configure_release_component(component1)
      _configure_release_component(component2)

      allow(Runner).to receive(:release_poll_time).and_return(0)
      allow(component1).to receive(:create_ad_release_dns_records)

      components = {
        "component1" => component1,
        "component2" => component2
      }

      allow(Defaults).to receive(:sections).and_return({
        :build => 1
      })

      allow(PipelineMetadataService).to receive(:save_metadata)

      allow(ServiceNow).to receive(:create_ci)

      successful_components, failed_components = Runner.release(components)

      expect(successful_components.count).to eq(2)
      expect(failed_components.count).to eq(0)
    end

    it 'traces failed components' do
      component1 = double(Consumable)
      component2 = double(Consumable)

      _configure_release_component(component1)
      _configure_release_component(component2)

      allow(Runner).to receive(:release_poll_time).and_return(0)
      allow(component1).to receive(:create_ad_release_dns_records)

      components = {
        "component1" => component1,
        "component2" => component2
      }

      allow(Defaults).to receive(:sections).and_return({
        :build => 1
      })

      allow(ServiceNow).to receive(:create_ci)
      allow(ThreadHelper).to receive(:wait_for_threads)
        .and_return([
                      [{ "item" => component1 }],
                      [{ "item" => component2 }]
                    ])

      successful_components, failed_components = Runner.release(components)

      expect(successful_components.count).to eq(1)
      expect(failed_components.count).to eq(1)
    end
  end

  context '.teardown' do
    def _configure_teardown_component(component)
      allow(component).to receive(:name_records).and_return([])
      allow(component).to receive(:stage).and_return("1")
      allow(component).to receive(:pre_teardown).and_return(nil)
      allow(component).to receive(:teardown)
      allow(component).to receive(:post_teardown).and_return(nil)
      allow(component).to receive(:finalise_security_rules)
      allow(component).to receive(:teardown_security_rules)
      allow(component).to receive(:teardown_security_items)

      allow(AwsHelper).to receive(:cfn_delete_stack)
    end

    it 'teardowns components' do
      component1 = double(Consumable)
      component2 = double(Consumable)

      _configure_teardown_component(component1)
      _configure_teardown_component(component2)

      components = {
        "component1" => component1,
        "component2" => component2
      }

      allow(Runner).to receive(:teardown_poll_time).and_return(0)

      successful_components, failed_components = Runner.teardown(components)
    end

    it 'teardowns released component' do
      component1 = double(Consumable)
      component2 = double(Consumable)

      _configure_teardown_component(component1)
      _configure_teardown_component(component2)

      components = {
        "component1" => component1,
        "component2" => component2
      }

      allow(Context).to receive_message_chain('persist.released_build_number')
        .and_return('1')

      allow(Context).to receive_message_chain('persist.remove_active_build')
        .and_return('1')

      allow(Runner).to receive(:teardown_poll_time).and_return(0)

      successful_components, failed_components = Runner.teardown(components)
    end

    it 'rejects to teardown released component on Prod' do
      component1 = double(Consumable)
      component2 = double(Consumable)

      _configure_teardown_component(component1)
      _configure_teardown_component(component2)

      components = {
        "component1" => component1,
        "component2" => component2
      }

      allow(Context).to receive_message_chain('persist.released_build_number')
        .and_return('42')

      allow(Defaults).to receive(:sections)
        .and_return({
          :build => '42',
          :env => 'prod'

        })

      allow(Context).to receive_message_chain('persist.remove_active_build')
      allow(Runner).to receive(:teardown_poll_time).and_return(0)

      expect {
        successful_components, failed_components = Runner.teardown(components)
      }.to raise_error(/teardown was attempted on a currently-released production build/)
    end

    it 'tearsdown released component on NonProd' do
      component1 = double(Consumable)
      component2 = double(Consumable)

      _configure_teardown_component(component1)
      _configure_teardown_component(component2)

      components = {
        "component1" => component1,
        "component2" => component2
      }

      allow(Context).to receive_message_chain('persist.released_build_number')
        .and_return('42')

      allow(Defaults).to receive(:sections)
        .and_return({
          :build => '42',
          :env => 'nonp'
        })

      allow(Context).to receive_message_chain('persist.remove_active_build')
      allow(Context).to receive_message_chain('persist.released_build_number=')

      allow(Runner).to receive(:teardown_poll_time).and_return(0)

      successful_components, failed_components = Runner.teardown(components)
    end

    it 'fails on force_teardown_of_released_build == false' do
      component1 = double(Consumable)
      component2 = double(Consumable)

      _configure_teardown_component(component1)
      _configure_teardown_component(component2)

      components = {
        "component1" => component1,
        "component2" => component2
      }

      allow(Context).to receive_message_chain('persist.released_build_number')
        .and_return('42')

      allow(Defaults).to receive(:sections)
        .and_return({
          :build => '42',
          :env => 'prod'
        })

      allow(Context).to receive_message_chain('persist.remove_active_build')
      allow(Context).to receive_message_chain('environment.variable')
        .with('force_teardown_of_released_build', nil)
        .and_return('false')

      allow(Runner).to receive(:teardown_poll_time).and_return(0)

      expect {
        successful_components, failed_components = Runner.teardown(components)
      }.to raise_error(/Teardown of the released build is rejected by pipeline/)
    end

    it 'teardowns on force_teardown_of_released_build == true' do
      component1 = double(Consumable)
      component2 = double(Consumable)

      _configure_teardown_component(component1)
      _configure_teardown_component(component2)

      components = {
        "component1" => component1,
        "component2" => component2
      }

      allow(Context).to receive_message_chain('persist.released_build_number')
        .and_return('42')

      allow(Defaults).to receive(:sections)
        .and_return({
          :build => '42',
          :env => 'prod'
        })

      allow(Context).to receive_message_chain('persist.remove_active_build')
      allow(Context).to receive_message_chain('persist.released_build_number=')

      allow(Context).to receive_message_chain('environment.variable')
        .with('force_teardown_of_released_build', nil)
        .and_return('true')

      allow(Runner).to receive(:teardown_poll_time).and_return(0)

      successful_components, failed_components = Runner.teardown(components)
    end
  end
end # RSpec.describe
