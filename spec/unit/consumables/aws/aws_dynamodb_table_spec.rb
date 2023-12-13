require 'consumables/aws/aws_dynamodb_table'
require 'util/nsupdate'
require 'consumables/aws/builders/dynamodb_table_builder'

RSpec.describe AwsDynamoDbTable do
  before(:context) do
    test_data_file = "#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"
    @test_data = YAML.load_file(
      test_data_file,
      permitted_classes: ['IamSecurityRule']
    )['UnitTest']
  end

  context '.initialize' do
    it 'initialize without error' do
      expect { AwsDynamoDbTable.new 'correct', @test_data['Input']['initialize']['correct'] }.not_to raise_exception
    end

    it 'fail initialize with error - multiple' do
      expect { AwsDynamoDbTable.new 'multiple', @test_data['Input']['initialize']['multiple'] }
        .to raise_error(RuntimeError, /This component does not support multiple/)
    end

    it 'fail initialize with error - wrong-type' do
      expect { AwsDynamoDbTable.new 'wrong-type', @test_data['Input']['initialize']['wrong-type'] }
        .to raise_error(RuntimeError, /is not supported by this component/)
    end

    it 'fail initialize with error - missing-table' do
      expect { AwsDynamoDbTable.new 'wrong-code', @test_data['Input']['initialize']['missing-table'] }
        .to raise_error(RuntimeError, /Must specify an AWS::DynamoDB::Table resource/)
    end

    it 'fail initialize with error - nil' do
      expect { AwsDynamoDbTable.new 'nil', @test_data['Input']['initialize']['nil'] }
        .to raise_error(RuntimeError, /Must specify a type for resource/)
    end
  end

  context '.security_items' do
    it 'returns security items' do
      aws_dynamodb_table = AwsDynamoDbTable.new 'correct', @test_data['Input']['initialize']['correct']
      aws_dynamodb_table.instance_variable_set(:@scheduled_actions, { dummy: 'action' })
      aws_dynamodb_table.instance_variable_set(:@backup_policy, { dummy: 'backup-policy' })
      security_items = aws_dynamodb_table.security_items
      expect(security_items).to eq @test_data['Output']['security_items']
    end
  end

  context '.security_rules' do
    it 'returns security rules' do
      aws_dynamodb_table = AwsDynamoDbTable.new 'correct', @test_data['Input']['initialize']['correct']
      allow(Context).to receive_message_chain('component.variable').and_return('dummy-arn')
      aws_dynamodb_table.instance_variable_set(:@scheduled_actions, { dummy: 'action' })
      aws_dynamodb_table.instance_variable_set(:@backup_policy, { dummy: 'backup-policy' })
      expect(aws_dynamodb_table.security_rules).to eq @test_data['Output']['security_rules']
    end
  end

  before (:context) do
    @aws_dynamodb_table = AwsDynamoDbTable.new 'correct', @test_data['Input']['initialize']['correct']
  end

  context '.deploy' do
    it 'deploys with new function stack successfully' do
      allow(@aws_dynamodb_table).to receive(:_build_template)
      allow(@aws_dynamodb_table).to receive(:security_rules)
      allow(@aws_dynamodb_table).to receive(:_update_security_rules)
      allow(@aws_dynamodb_table).to receive(:deploy_ad_dns_records)
      allow(Context).to receive_message_chain('component.variable')

      allow(AwsHelper).to receive(:cfn_create_stack).and_return(
        'StackId' => 'dummy-stack-id',
        'StackName' => 'dummy-stack-name'
      )
      allow(Context).to receive_message_chain('component.set_variables')

      expect { @aws_dynamodb_table.deploy }.not_to raise_error
    end

    it 'deploys with auto scaling stack successfully' do
      @aws_dynamodb_table = AwsDynamoDbTable.new 'correct', @test_data['Input']['initialize']['autoscaling']
      allow(@aws_dynamodb_table).to receive(:_build_template)
      allow(@aws_dynamodb_table).to receive(:security_rules)
      allow(@aws_dynamodb_table).to receive(:_update_security_rules)
      allow(@aws_dynamodb_table).to receive(:deploy_ad_dns_records)
      allow(Context).to receive_message_chain('component.variable')

      allow(AwsHelper).to receive(:cfn_create_stack).and_return(
        'StackId' => 'dummy-stack-id',
        'StackName' => 'dummy-stack-name'
      )
      allow(Context).to receive_message_chain('component.set_variables')

      expect { @aws_dynamodb_table.deploy }.not_to raise_error
    end

    it 'fails with Failed to create stack' do
      allow(@aws_dynamodb_table).to receive(:_build_template)
      allow(@aws_dynamodb_table).to receive(:security_rules)
      allow(@aws_dynamodb_table).to receive(:_update_security_rules)
      allow(@aws_dynamodb_table).to receive(:deploy_ad_dns_records)
      allow(Context).to receive_message_chain('component.variable')

      allow(AwsHelper).to receive(:cfn_create_stack).and_raise(RuntimeError)
      allow(Context).to receive_message_chain('component.set_variables')

      expect { @aws_dynamodb_table.deploy }.to raise_exception /Failed to create stack/
    end

    it 'deploys with Failed to deploy DNS records' do
      allow(@aws_dynamodb_table).to receive(:_build_template)
      allow(@aws_dynamodb_table).to receive(:security_rules)
      allow(@aws_dynamodb_table).to receive(:_update_security_rules)
      allow(Context).to receive_message_chain('component.variable')
      allow(@aws_dynamodb_table).to receive(:deploy_ad_dns_records).and_raise(RuntimeError)

      allow(AwsHelper).to receive(:cfn_create_stack).and_return(
        'StackId' => 'dummy-stack-id',
        'StackName' => 'dummy-stack-name'
      )
      allow(Context).to receive_message_chain('component.set_variables')

      expect { @aws_dynamodb_table.deploy }.to raise_exception /Failed to deploy DNS records/
    end
  end

  before (:context) do
    @aws_dynamodb_table = AwsDynamoDbTable.new 'correct', @test_data['Input']['initialize']['correct']
  end

  context '.release' do
    it 'success' do
      expect { @aws_dynamodb_table.release } .not_to raise_error
    end
  end

  before (:context) do
    @aws_dynamodb_table = AwsDynamoDbTable.new 'correct', @test_data['Input']['initialize']['correct']
  end

  context '.teardown' do
    it 'seccessfully executes teardown' do
      @aws_dynamodb_table.instance_variable_set(:@backup_policy, { dummy: 'backup-policy' })
      allow(Context).to receive_message_chain('component.sg_id').and_return('sg-12345678')

      allow(Context).to receive_message_chain('component.stack_id').and_return('dummy-stack-id')
      allow(AwsHelper).to receive(:cfn_delete_stack).and_return(nil)

      allow(@aws_dynamodb_table).to receive(:_clean_ad_deployment_dns_record)
      allow(@aws_dynamodb_table).to receive(:_clean_ad_release_dns_record)

      expect { @aws_dynamodb_table.teardown }.not_to raise_error
    end

    it 'fails with - Failed to delete stack' do
      @aws_dynamodb_table.instance_variable_set(:@backup_policy, { dummy: 'backup-policy' })
      allow(Context).to receive_message_chain('component.sg_id').and_return('sg-12345678')

      allow(Context).to receive_message_chain('component.stack_id').and_return('dummy-stack-id')
      allow(AwsHelper).to receive(:cfn_delete_stack).and_raise(RuntimeError)
      expect(Log).to receive(:warn).with(/Failed to delete stack/)

      allow(@aws_dynamodb_table).to receive(:_clean_ad_deployment_dns_record)
      allow(@aws_dynamodb_table).to receive(:_clean_ad_release_dns_record)

      expect { @aws_dynamodb_table.teardown }.to raise_exception(RuntimeError)
    end

    it 'fails with - Failed to remove AD DNS records during teardown' do
      @aws_dynamodb_table.instance_variable_set(:@backup_policy, { dummy: 'backup-policy' })
      allow(Context).to receive_message_chain('component.sg_id').and_return('sg-12345678')

      allow(Context).to receive_message_chain('component.stack_id').and_return('dummy-stack-id')
      allow(AwsHelper).to receive(:cfn_delete_stack).and_return(nil)

      allow(@aws_dynamodb_table).to receive(:_clean_ad_deployment_dns_record)
      allow(@aws_dynamodb_table).to receive(:_clean_ad_release_dns_record).and_raise(RuntimeError)
      expect(Log).to receive(:warn).with(/Failed to remove AD DNS records during teardown/)

      expect { @aws_dynamodb_table.teardown }.to raise_exception(RuntimeError)
    end
  end

  context '._build_template' do
    it 'successfully executes' do
      aws_dynamodb_table = AwsDynamoDbTable.new('dynamodb', @test_data['Input']['_full_template']['Valid'])
      aws_dynamodb_table.instance_variable_set(:@scheduled_actions, { dummy: 'action' })

      allow(aws_dynamodb_table).to receive(:_check_billing_type)
      allow(aws_dynamodb_table).to receive(:_process_dynamodb_table)
      allow(aws_dynamodb_table).to receive(:_process_dynamodb_scheduled_actions)
      allow(aws_dynamodb_table).to receive(:_parse_dynamodb_scheduled_action)
      allow(Context).to receive_message_chain("component.role_arn").and_return('InstanceRoleName-123')

      aws_dynamodb_table.instance_variable_set(:@backup_policy, { dummy: 'backup-policy' })
      allow(Context).to receive_message_chain("component.role_arn").and_return('InstanceRoleName-123')
      allow(Context).to receive_message_chain("component.sg_id").and_return(['sg-1234566'])
      allow(Context).to receive_message_chain("component.replace_variables")
      allow(aws_dynamodb_table).to receive(:_parse_dynamodb_backup_policy)
      allow(aws_dynamodb_table).to receive(:_process_backup_policy)

      allow(Defaults).to receive(:r53_dns_zone?).and_return(true)
      allow(aws_dynamodb_table).to receive(:_process_deploy_r53_dns_records)

      expect { aws_dynamodb_table.send(:_build_template) }.not_to raise_exception
    end
  end

  context '._check_billing_type' do
    it 'check if BillingMode tag exists' do
      billing_mode = @test_data['Input']['initialize']['ondemand']["Configuration"]["MyTable"]

      expect { (billing_mode).has_key? "BillingMode" }.not_to raise_exception
    end

    it 'check valid tags for PAY_PER_REQUEST' do
      billing_mode = @test_data['Input']['initialize']['ondemand']["Configuration"]["MyTable"]["BillingMode"]

      expect { billing_mode.eql? "PAY_PER_REQUEST" }.not_to raise_exception
    end

    it 'check valid tags for PROVISIONED' do
      billing_mode = @test_data['Input']['initialize']['ondemand-provisioned']["Configuration"]["MyTable"]["BillingMode"]

      expect { billing_mode.eql? "PROVISIONED" }.not_to raise_exception
    end

    it 'check invalid as template for ondemand' do
      billing_mode = @test_data['Input']['initialize']['ondemand-invalid']["Configuration"]["MyTable"]

      expect { (billing_mode).has_key? "ProvisionedThroughput" }.not_to raise_exception
    end
  end
end # RSpec.describe
