$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws")
require 'aws_ecs_task'
require 'builders/task_definition_builder'

RSpec.describe AwsECSTask do
  before(:context) do
    test_data_file = "#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"
    @test_data = YAML.load_file(
      test_data_file,
      permitted_classes: ['IamSecurityRule']
    )['UnitTest']
  end

  context '.initialize' do
    it 'initialize without error' do
      expect { AwsECSTask.new 'correct', @test_data['Input']['initialize']['correct'] }.not_to raise_exception
    end

    it 'fail initialize with error - invalid resource' do
      expect { AwsECSTask.new 'multiple', @test_data['Input']['initialize']['invalid-resource'] }
        .to raise_error(RuntimeError, /is not supported by this component/)
    end
  end

  context '.security_items' do
    it 'returns security items' do
      aws_ecs_task = AwsECSTask.new 'correct', @test_data['Input']['initialize']['correct']
      allow(Context).to receive_message_chain('asir.managed_policy_arn').and_return('arn::policy/managed-policy')
      expect(aws_ecs_task.security_items).to eql @test_data["Output"]["SecurityItems"]
    end
  end

  context '.security_rules' do
    it 'returns security rules' do
      aws_ecs_task = AwsECSTask.new 'correct', @test_data['Input']['initialize']['correct']
      allow(Context).to receive_message_chain("kms.secrets_key_arn").and_return("arn:aws:kms:ap-southeast-2:111122223333:key/dummyarn")
      allow(Context).to receive_message_chain('s3.ams_bucket_arn').and_return('arn:aws:s3:::bucket-ams-test')
      allow(Context).to receive_message_chain('s3.qda_bucket_arn').and_return('arn:aws:s3:::bucket-qda-test')
      allow(Context).to receive_message_chain('s3.as_bucket_arn').and_return('arn:aws:s3:::bucket-as-test')

      # Remove !ruby/object to parse back into Ruby hash to then check equality
      a = aws_ecs_task.security_rules.to_yaml.gsub('!ruby/object:IamSecurityRule', '')
      b = @test_data['Output']['SecurityRules'].to_yaml.gsub('!ruby/object:IamSecurityRule', '')

      expect(Psych.load(a)).to eql Psych.load(b)
    end
  end

  before (:context) do
    correct_input = Marshal.load(Marshal.dump(@test_data['Input']['initialize']['correct']))
    @aws_ecs_task = AwsECSTask.new('correct', correct_input)
  end

  context '.name_records' do
    it 'return name records' do
      expect(@aws_ecs_task.name_records).to be_a(Hash)
    end
  end

  context '.deploy' do
    it 'deploys with new function stack successfully' do
      allow(@aws_ecs_task).to receive(:_update_security_rules)
      allow(Context).to receive_message_chain("environment.subnet_ids").and_return(["subnet-123", "subnet-456"])
      allow(Defaults).to receive(:component_stack_name).and_return('dummy-stack-name')
      allow(Defaults).to receive(:get_tags).and_return([])
      allow(AwsHelper).to receive(:cfn_create_stack).and_return(
        'StackId' => 'dummy-stack-id',
        'StackName' => 'dummy-stack-name'
      )
      expect { @aws_ecs_task.deploy }.not_to raise_error
    end

    it 'deploys with new function stack successfully' do
      allow(@aws_ecs_task).to receive(:_update_security_rules)
      allow(Context).to receive_message_chain("environment.subnet_ids").and_return(["subnet-123", "subnet-456"])
      allow(Defaults).to receive(:component_stack_name).and_return('dummy-stack-name')
      allow(Defaults).to receive(:get_tags).and_return([])
      allow(AwsHelper).to receive(:cfn_create_stack).and_return(
        'StackId' => 'dummy-stack-id',
        'StackName' => 'dummy-stack-name'
      )
      expect { @aws_ecs_task.deploy }.not_to raise_error
    end

    it 'raise on error' do
      allow(@aws_ecs_task).to receive(:_update_security_rules)
      allow(Context).to receive_message_chain("environment.subnet_ids").and_return(["subnet-123", "subnet-456"])
      allow(Defaults).to receive(:component_stack_name).and_return('dummy-stack-name')
      allow(Defaults).to receive(:get_tags).and_return([])
      allow(AwsHelper).to receive(:cfn_create_stack).and_raise(ActionError)
      expect { @aws_ecs_task.deploy }.to raise_error(/Failed to create stack/)
    end
  end

  context '.release' do
    it 'successfully executes release' do
      expect { @aws_ecs_task.release } .not_to raise_error
    end
  end

  context '.teardown' do
    it 'successfully executes teardown' do
      allow(Context).to receive_message_chain('component.stack_id').and_return('dummy-stack-id')
      allow(AwsHelper).to receive(:cfn_delete_stack).and_return(nil)
      allow(@aws_ecs_task).to receive(:_clean_ad_deployment_dns_record)
      allow(@aws_ecs_task).to receive(:_clean_ad_release_dns_record)
      expect { @aws_ecs_task.teardown }.not_to raise_error
    end

    it 'fails to delete stack due to cfn exception' do
      allow(Context).to receive_message_chain('component.stack_id').and_return('dummy-stack-id')
      allow(AwsHelper).to receive(:cfn_delete_stack).and_raise(RuntimeError)
      allow(@aws_ecs_task).to receive(:_clean_ad_deployment_dns_record)
      allow(@aws_ecs_task).to receive(:_clean_ad_release_dns_record)
      expect { @aws_ecs_task.teardown }.to raise_exception(RuntimeError)
    end
  end

  context '._full_template' do
  end
end # RSpec.describe
