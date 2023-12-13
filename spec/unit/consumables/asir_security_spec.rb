$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib/consumables"))
require 'asir_security'
$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib/util"))
require 'thread_helper'

RSpec.describe AsirSecurity do
  before(:context) do
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))['UnitTest']
  end

  context '._build_rules_template' do
    it 'returns security rules template' do
      input = @test_data['Input']['_build_rules_template']
      output = @test_data['Output']['_build_rules_template']

      input['Mock'].each { |mock|
        item = receive_message_chain(mock['MessageChain'])
        item = item.with(*mock['With']) unless mock['With'].nil?
        item = item.and_return(mock['Return'])
        allow(Kernel.const_get(mock['Object'])).to item
      }
      expect(AsirSecurity._build_rules_template(input['destination_sg_id'], input['destination_rules'])).to eq output
    end

    it 'created stub template on empty ASIR rules' do
      allow(AsirSecurity).to receive(:_process_security_rules)

      result = AsirSecurity._build_rules_template([], [])

      expect(result["Resources"]["NoRules"]).to eq({
        "Type" => "AWS::CloudFormation::WaitConditionHandle",
        "Properties" => {}
      })
    end
  end

  context '.deploy_security_items' do
    it 'deploys security items' do
      load_mocks @test_data['Input']['deploy_security_items']['Mock']
      expect { AsirSecurity.deploy_security_items }.not_to raise_error
    end
  end

  context '.deploy_security_rules' do
    it 'deploys security rules' do
      load_mocks @test_data['Input']['deploy_security_rules']['Mock']
      expect { AsirSecurity.deploy_security_rules() }.not_to raise_error
    end

    it 'deploys rules with non-existing destination_rules_stack_id' do
      rules = [
        { 'destination' => '1' },
        { 'destination' => '2' },
      ]

      allow(AsirSecurity).to receive(:_rules_in_set)
        .and_return(rules)

      AsirSecurity.deploy_security_rules()
    end

    it 'deploys rules with existing destination_rules_stack_id' do
      rules = [
        { 'destination' => '1' },
        { 'destination' => '2' },
      ]

      allow(AsirSecurity).to receive(:_rules_in_set)
        .and_return(rules)

      allow(AsirSecurity).to receive(:_rules_with_destination)
      allow(AsirSecurity).to receive(:_build_rules_template)

      allow(AwsHelper).to receive(:cfn_update_stack)

      allow(Context).to receive_message_chain('asir.set_name')
      allow(Context).to receive_message_chain('asir.destination_rules_template')
      allow(Context).to receive_message_chain('asir.set_destination_rules_details')
      allow(Context).to receive_message_chain('asir.destination_rules_stack_id')
        .and_return('1')
      allow(Context).to receive_message_chain('asir.destination_sg_id')
        .and_return('1')

      allow(AwsHelper).to receive(:cfn_update_stack).and_return({
        "StackId" => {}
      })
      allow(Context).to receive_message_chain('asir.set_destination_rules_details')
      allow(AsirSecurity).to receive(:security_stack_update_poll_time).and_return(0)

      AsirSecurity.deploy_security_rules()
    end

    it 'deploys rules update with existing destination_rules_stack_id' do
      rules = [
        { 'destination' => '1' },
        { 'destination' => '2' },
      ]

      allow(AsirSecurity).to receive(:_rules_in_set)
        .and_return(rules)

      allow(AsirSecurity).to receive(:_rules_with_destination)
      allow(AsirSecurity).to receive(:_build_rules_template)

      allow(AwsHelper).to receive(:cfn_update_stack)

      allow(Context).to receive_message_chain('asir.set_name')
      allow(Context).to receive_message_chain('asir.destination_rules_template')
        .and_return('new template')
      allow(Context).to receive_message_chain('asir.set_destination_rules_details')
      allow(Context).to receive_message_chain('asir.destination_rules_stack_id')
        .and_return('1')
      allow(Context).to receive_message_chain('asir.destination_sg_id')
        .and_return('2')

      allow(AwsHelper).to receive(:cfn_update_stack).and_return({
        "StackId" => {}
      })
      allow(Context).to receive_message_chain('asir.set_destination_rules_details')
      allow(AsirSecurity).to receive(:security_stack_update_poll_time).and_return(0)

      AsirSecurity.deploy_security_rules()
    end
  end

  context '._deploy_asir_destination_sg' do
    it 'deploys asir desination sg' do
      load_mocks @test_data['Input']['_deploy_asir_destination_sg']['Mock']
      expect { AsirSecurity._deploy_asir_destination_sg }.not_to raise_error
    end

    it 'loads existing stack output' do
      allow(AwsHelper).to receive(:cfn_stack_exists)
        .and_return(1)

      allow(AwsHelper).to receive(:cfn_get_stack_outputs)
        .and_return({
          "AsirDestinationGroupId" => 'group-1'
        })

      AsirSecurity._deploy_asir_destination_sg
    end

    it 'raises on empty existing stack output' do
      allow(AwsHelper).to receive(:cfn_stack_exists)
        .and_return(1)

      allow(AwsHelper).to receive(:cfn_get_stack_outputs)
        .and_return({
          "AsirDestinationGroupId" => nil
        })

      expect {
        AsirSecurity._deploy_asir_destination_sg
      }.to raise_error(/An error occurred loading ASIR Destination SG details/)
    end
  end

  context '._deploy_asir_source_sg' do
    it 'deploys asir source sg' do
      load_mocks @test_data['Input']['_deploy_asir_source_sg']['Mock']
      expect { AsirSecurity._deploy_asir_source_sg(123) }.not_to raise_error
    end

    it 'loads existing stack output' do
      allow(AwsHelper).to receive(:cfn_stack_exists)
        .and_return(1)

      allow(AwsHelper).to receive(:cfn_get_stack_outputs)
        .and_return({
          "AsirSourceGroupId" => 'group-1'
        })

      AsirSecurity._deploy_asir_source_sg('tmp-1')
    end

    it 'raises on empty existing stack output' do
      allow(AwsHelper).to receive(:cfn_stack_exists)
        .and_return(1)

      allow(AwsHelper).to receive(:cfn_get_stack_outputs)
        .and_return({
          "AsirSourceGroupId" => nil
        })

      expect {
        AsirSecurity._deploy_asir_source_sg('tmp-1')
      }.to raise_error(/An error occurred loading ASIR Source SG details/)
    end
  end

  context '._deploy_asir_managed_policy' do
    it 'deploys asir managed policy' do
      load_mocks @test_data['Input']['_deploy_asir_managed_policy']['Mock']
      expect { AsirSecurity._deploy_asir_managed_policy(123) }.not_to raise_error
    end

    it 'loads existing asir managed policy stack' do
      allow(AwsHelper).to receive(:cfn_stack_exists)
        .and_return(1)

      allow(AwsHelper).to receive(:cfn_get_stack_outputs)
        .and_return({
          "AsirManagedPolicyArn" => 'arn-1'
        })

      allow(Context).to receive_message_chain('asir.set_managed_policy_details')

      AsirSecurity._deploy_asir_managed_policy('tmp-set')
    end

    it 'raises on failed load of existing asir managed policy stack' do
      allow(AwsHelper).to receive(:cfn_stack_exists)
        .and_return(1)

      allow(AwsHelper).to receive(:cfn_get_stack_outputs)
        .and_return({
          "AsirManagedPolicyArn" => nil
        })

      allow(Context).to receive_message_chain('asir.set_managed_policy_details')

      expect {
        AsirSecurity._deploy_asir_managed_policy('tmp-set')
      }.to raise_error(/Stack did not output an ASIR managed policy ARN/)
    end

    it 'uses partial output on ActionError' do
      allow(AwsHelper).to receive(:cfn_stack_exists)
        .and_return(1)

      allow(AwsHelper).to receive(:cfn_get_stack_outputs)
        .and_raise(ActionError.new('action error tmp'))

      allow(Context).to receive_message_chain('asir.set_managed_policy_details')

      expect {
        AsirSecurity._deploy_asir_managed_policy('tmp-set')
      }.to raise_error(/An error occurred loading ASIR managed policy details - ActionError/)
    end
  end

  context '._deploy_asir_rules_stack' do
    it 'deploys asir rules stack' do
      load_mocks @test_data['Input']['_deploy_asir_rules_stack']['Mock']
      expect { AsirSecurity._deploy_asir_rules_stack }.not_to raise_error
    end

    it 'loads existing asir rules stack' do
      allow(AwsHelper).to receive(:cfn_stack_exists)
        .and_return(1)

      allow(AwsHelper).to receive(:cfn_get_template)

      AsirSecurity._deploy_asir_rules_stack
    end

    it 'raises on failed stack provision' do
      allow(AwsHelper).to receive(:cfn_stack_exists)
        .and_return(nil)

      allow(AwsHelper).to receive(:cfn_create_stack)
        .and_raise('cannot create asir rule stack')

      expect {
        AsirSecurity._deploy_asir_rules_stack
      }.to raise_error(/cannot create asir rule stack/)
    end
  end

  context '._rules_in_set' do
    it 'queries dynamo db' do
      queryOutput = double(Aws::DynamoDB::Types::QueryOutput)
      allow(AwsHelper).to receive(:dynamodb_query) .and_return(queryOutput)
      allow(queryOutput).to receive(:items)
      expect { AsirSecurity._rules_in_set(123) }.not_to raise_error
    end
  end

  context '._rules_with_destination' do
    it 'queries dynamo db' do
      queryOutput = double(Aws::DynamoDB::Types::QueryOutput)
      allow(AwsHelper).to receive(:dynamodb_query) .and_return(queryOutput)
      allow(queryOutput).to receive(:items)
      expect { AsirSecurity._rules_with_destination(123) }.not_to raise_error
    end
  end
end
