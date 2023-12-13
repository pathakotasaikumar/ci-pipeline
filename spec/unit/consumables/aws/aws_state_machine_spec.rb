$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws")
require 'aws_state_machine'
require 'builders/step_functions_state_machine_builder'

RSpec.describe AwsStateMachine do
  before(:context) do
    test_data_file = "#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"
    @test_data = YAML.load_file(
      test_data_file,
      permitted_classes: ['IamSecurityRule', Symbol],
      aliases: true
    )['UnitTest']
  end

  context '.initialize' do
    it 'initialize without error' do
      expect { AwsStateMachine.new 'correct', @test_data['Input']['initialize']['correct'] }.not_to raise_exception
    end

    it 'fail initialize with error - multiple' do
      expect { AwsStateMachine.new 'multiple', @test_data['Input']['initialize']['multiple'] }
        .to raise_error(RuntimeError, /This component does not support multiple/)
    end

    it 'fail initialize with error - wrong-type' do
      expect { AwsStateMachine.new 'wrong-type', @test_data['Input']['initialize']['wrong-type'] }
        .to raise_error(RuntimeError, /Must specify an AWS::StepFunctions::StateMachine resource/)
    end

    it 'fail initialize with error - missing resource' do
      expect { AwsStateMachine.new 'wrong-type', @test_data['Input']['initialize']['missing-resource'] }
        .to raise_error(RuntimeError, /is not supported by this component/)
    end

    it 'fail initialize with error - nil' do
      expect { AwsStateMachine.new 'nil', @test_data['Input']['initialize']['nil'] }
        .to raise_error(RuntimeError, /Must specify an AWS::StepFunctions::StateMachine resource/)
    end
  end

  context '.security_rules' do
    it 'returns security rules' do
      state_machine = AwsStateMachine.new 'correct', @test_data['Input']['initialize']['correct']
      allow(Context).to receive_message_chain('component.variable').and_return('dummy-arn')
      allow(state_machine).to receive(:_resource_arns).and_return(['dummy-arn1', 'dummy-arn2'])
      security_rules = state_machine.security_rules
      expect(security_rules).to eq @test_data['Output']['security_rules']
    end
  end

  context '.security_items' do
    it 'returns security items' do
      state_machine = AwsStateMachine.new 'correct', @test_data['Input']['initialize']['correct']
      security_items = state_machine.security_items
      expect(security_items).to eq @test_data['Output']['security_items']
    end
  end

  before (:context) do
    @state_machine = AwsStateMachine.new 'correct', @test_data['Input']['initialize']['correct']
  end

  context '.deploy' do
    it 'deploys with new function stack successfully' do
      allow(Defaults).to receive(:component_stack_name)
      allow(@state_machine).to receive(:_build_template)
      allow(Context).to receive_message_chain('component.set_variables')

      allow(@state_machine).to receive(:_upload_package_artefacts)
      allow(@state_machine).to receive(:_update_security_rules)
      allow(@state_machine).to receive(:security_rules)

      # Mock creation of a stack
      allow(AwsHelper).to receive(:cfn_create_stack).and_return(
        'StackId' => 'dummy-stack-id',
        'StackName' => 'dummy-stack-name'
      )
      allow(Context).to receive_message_chain('component.variable')
      allow(@state_machine).to receive(:deploy_ad_dns_records)

      expect { @state_machine.deploy }.not_to raise_error
    end

    it 'fails with new function stack successfully' do
      allow(Defaults).to receive(:component_stack_name)
      allow(@state_machine).to receive(:_build_template)
      allow(Context).to receive_message_chain('component.set_variables')

      allow(@state_machine).to receive(:_upload_package_artefacts)
      allow(@state_machine).to receive(:_update_security_rules)
      allow(@state_machine).to receive(:security_rules)

      # Mock creation of a stack
      allow(AwsHelper).to receive(:cfn_create_stack).and_raise(StandardError)

      expect { @state_machine.deploy }.to raise_exception /Failed to create stack/
    end
  end

  before (:context) do
    @state_machine = AwsStateMachine.new 'correct', @test_data['Input']['initialize']['correct']
  end

  context '.release' do
    it 'success' do
      expect { @state_machine.release } .not_to raise_error
    end
  end

  before (:context) do
    @state_machine = AwsStateMachine.new 'correct', @test_data['Input']['initialize']['correct']
  end

  context '.teardown' do
    it 'seccessfully executes teardown' do
      allow(Context).to receive_message_chain('component.sg_id').and_return('dummy-sg')

      allow(Context).to receive_message_chain('component.stack_id').and_return('dummy-stack-id')
      allow(AwsHelper).to receive(:cfn_delete_stack).and_return(nil)
      allow(@state_machine).to receive(:_clean_ad_deployment_dns_record)
      allow(@state_machine).to receive(:_clean_ad_release_dns_record)

      expect { @state_machine.teardown }.not_to raise_error
    end

    it 'fails with - Failed to delete stack' do
      allow(Context).to receive_message_chain('component.sg_id').and_return('dummy-sg')

      allow(Context).to receive_message_chain('component.stack_id').and_return('dummy-stack-id')
      allow(AwsHelper).to receive(:cfn_delete_stack).and_raise(StandardError)
      allow(@state_machine).to receive(:_clean_ad_deployment_dns_record)
      allow(@state_machine).to receive(:_clean_ad_release_dns_record).and_raise(StandardError)

      expect { @state_machine.teardown }.to raise_exception StandardError
    end
  end

  context '._build_template' do
    it 'successfully executes' do
      state_machine = AwsStateMachine.new('state_machine', @test_data['Input']['_full_template']['Valid'])
      state_machine_definition = { "RetainerWorkflows" => @test_data['Input']['_full_template']['Valid']['Configuration']['RetainerWorkflow'] }


      allow(Context).to receive_message_chain('component.role_arn').and_return('dummy-role-arn')
      allow(Context).to receive_message_chain('component.sg_id').and_return('dummy-sg')
      allow(Context).to receive_message_chain('asir.source_sg_id').and_return('dummy-sg')
      allow(state_machine).to receive(:_process_events_rule)
      allow(state_machine).to receive(:_process_lambda_function)
      allow(state_machine).to receive(:_states_execution_role).and_return('dummy-execution-role')
      allow(Defaults).to receive(:txt_by_dns).and_return('dummy-destination-location')
      allow(Context).to receive_message_chain('component.replace_variables').and_return(state_machine_definition)
      template = state_machine.send(:_build_template)
      expect(template).to eq @test_data['Output']['_full_template']
    end

    it 'generates default / customised templates for Route53 Dns zone' do
      valid_component_name = "STF"
      allow(Defaults).to receive(:dns_zone).and_return(Defaults.r53_dns_zone)

      state_machine = AwsStateMachine.new(valid_component_name, @test_data['Input']['_build_template']['Customised'])
      expect(state_machine.send :_build_template).to eq(@test_data['Output']['_build_template']['Customised']['Route53'])
    end
  end

  context '._states_execution_role' do
    it 'successfully executes' do
      state_machine = AwsStateMachine.new('state_machine', @test_data['Input']['_full_template']['Valid'])
      allow(Context).to receive_message_chain('environment.account_id').and_return('dummy-account')
      allow(Context).to receive_message_chain('environment.region').and_return('dummy-region')
      Log.debug state_machine.send(:_states_execution_role)
      expect {
        state_machine.send(:_states_execution_role)
      }.not_to raise_exception
    end
  end

  context '._resource_arns' do
    it 'successfully executes' do
      state_machine = AwsStateMachine.new('state_machine', @test_data['Input']['_full_template']['Valid'])
      allow(Context).to receive_message_chain('environment.account_id').and_return('dummy-account')
      allow(Context).to receive_message_chain('environment.region').and_return('dummy-region')

      Log.debug state_machine.send(:_resource_arns)
      expect {
        state_machine.send(:_resource_arns)
      }.not_to raise_exception
    end
  end
end # RSpec.describe
