$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib/consumables/aws/"))
require 'consumables/aws/actions/execute_state_machine'
require 'consumable'

RSpec.describe ExecuteStateMachine do
  before do
    @args = {
      params: {
        'StateMachineName' => 'TestMachine',
        'Input' => {
          'var1' => '1',
          'var2' => '2'
        }
      },
      stage: 'PreRelease',
      step: '01'
    }
  end

  context 'initialize' do
    it 'successfully initialises ' do
      instance = double Consumable
      allow(instance).to receive(:type).and_return('aws/state-machine')
      expect {
        kwargs = { component: instance }.merge @args
        @execute_state_machine = ExecuteStateMachine.new(**kwargs)
      }.not_to raise_exception
    end

    it 'fails with - Parameter/LambdaFunction must be specified' do
      args = {
        params: {
          'LambdaFunction' => '',
          'Target' => '@deployed',
          'Payload' => {
            'var1' => '1',
            'var2' => '2'
          }
        },
        stage: "PreRelease",
        step: "01"
      }
      instance = double Consumable
      allow(instance).to receive(:type).and_return('aws/state-machine')
      expect {
        kwargs = { component: instance }.merge(args)
        @execute_state_machine = ExecuteStateMachine.new(**kwargs)
      }.to raise_exception /Parameter\/StateMachine must be specified/
    end
  end

  context 'invoke' do
    it 'successfully executes, skips wait' do
      args = {
        params: {
          'StateMachineName' => 'TestMachine',
          'WaitForCompletion' => 'false',
          'Input' => {
            'var1' => '1',
            'var2' => '2'
          }
        },
        stage: 'PreRelease',
        step: '01'
      }

      instance = double Consumable
      allow(instance).to receive(:type).and_return('aws/state-machine')
      allow(instance).to receive(:component_name).and_return('instance')
      kwargs = { component: instance }.merge args
      expect { @execute_state_machine = ExecuteStateMachine.new(**kwargs) }.not_to raise_exception

      allow(@execute_state_machine).to receive(:_state_machine_arn)
      allow(Context).to receive_message_chain('component.replace_variables')
      allow(AwsHelper).to receive(:states_start_execution).and_return(status_code: 200)

      expect { @execute_state_machine.invoke }.not_to raise_exception
    end

    it 'successfully executes, waits' do
      args = {
        params: {
          'StateMachineName' => 'TestMachine',
          'WaitForCompletion' => 'true',
          'Input' => {
            'var1' => '1',
            'var2' => '2'
          }
        },
        stage: 'PreRelease',
        step: '01'
      }

      instance = double Consumable
      allow(instance).to receive(:type).and_return('aws/state-machine')
      allow(instance).to receive(:component_name).and_return('instance')
      kwargs = { component: instance }.merge args
      execute_state_machine = ExecuteStateMachine.new(**kwargs)

      allow(execute_state_machine).to receive(:_state_machine_arn).and_return('dummy-state-machine-arn')
      allow(Context).to receive_message_chain('component.replace_variables')
      allow(AwsHelper).to receive(:states_start_execution).and_return('dummy-execution-arn')
      allow(AwsHelper).to receive(:states_wait_until_complete)
      allow(AwsHelper).to receive(:states_execution_result).and_return("{\"status\":\"OK\"}")

      expect { execute_state_machine.invoke }.not_to raise_exception
    end

    it 'fails with - Failed to execute \'instance\' action ExecuteStateMachine' do
      args = {
        params: {
          'StateMachineName' => 'TestMachine',
          'WaitForCompletion' => 'true',
          'Input' => {
            'var1' => '1',
            'var2' => '2'
          }
        },
        stage: 'PreRelease',
        step: '01'
      }

      instance = double Consumable
      allow(instance).to receive(:type).and_return('aws/state-machine')
      allow(instance).to receive(:component_name).and_return('instance')
      kwargs = { component: instance }.merge args
      execute_state_machine = ExecuteStateMachine.new(**kwargs)

      allow(execute_state_machine).to receive(:_state_machine_arn).and_return('dummy-state-machine-arn')
      allow(Context).to receive_message_chain('component.replace_variables')
      allow(AwsHelper).to receive(:states_start_execution).and_raise(StandardError)

      expect { execute_state_machine.invoke }.to raise_exception /Failed to execute \'instance\' action ExecuteStateMachine/
    end
  end

  context '_state_machine_arn' do
    it 'successfully executes' do
      args = {
        params: {
          'StateMachineName' => 'TestMachine',
          'WaitForCompletion' => 'true',
          'Input' => {
            'var1' => '1',
            'var2' => '2'
          }
        },
        stage: 'PreRelease',
        step: '01'
      }

      instance = double Consumable
      allow(instance).to receive(:type).and_return('aws/state-machine')
      allow(instance).to receive(:component_name).and_return('instance')
      kwargs = { component: instance }.merge args
      execute_state_machine = ExecuteStateMachine.new(**kwargs)
      allow(Context).to receive_message_chain('component.variable').and_return('test-machine-arn')
      expect(execute_state_machine.send(:_state_machine_arn, 'test-machine-name')).to eq('test-machine-arn')
    end
  end
end
