$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws")
require 'aws_vpc_endpoint_service'

RSpec.describe AwsVPCEndpointService do
  before(:context) do
    test_data_file = "#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"
    @test_data = YAML.load_file(test_data_file)['UnitTest']
  end

  context '.initialize' do
    it 'initialize without error' do
      expect { AwsVPCEndpointService.new 'correct', @test_data['Input']['initialize']['correct'] }.not_to raise_exception
    end

    it 'fail initialize with error - invalid resource' do
      expect { AwsVPCEndpointService.new 'invalid', @test_data['Input']['initialize']['invalid-resource'] }
        .to raise_error(RuntimeError, /is not supported by this component/)
    end
  end

  context '.security_items' do
    it 'returns security items' do
      aws_vpc_endpoint_service = AwsVPCEndpointService.new 'correct', @test_data['Input']['initialize']['correct']
      allow(Context).to receive_message_chain('asir.managed_policy_arn').and_return('arn::policy/managed-policy')
      expect(aws_vpc_endpoint_service.security_items).to eql @test_data["Output"]["SecurityItems"]
    end
  end

  context '.security_rules' do
    it 'returns security rules' do
      aws_vpc_endpoint_service = AwsVPCEndpointService.new 'correct', @test_data['Input']['initialize']['correct']
      allow(Context).to receive_message_chain("kms.secrets_key_arn").and_return("arn:aws:kms:ap-southeast-2:111122223333:key/dummyarn")
      allow(Context).to receive_message_chain('s3.ams_bucket_arn').and_return('arn:aws:s3:::bucket-ams-test')
      allow(Context).to receive_message_chain('s3.qda_bucket_arn').and_return('arn:aws:s3:::bucket-qda-test')
      allow(Context).to receive_message_chain('s3.as_bucket_arn').and_return('arn:aws:s3:::bucket-as-test')
      expect(aws_vpc_endpoint_service.security_rules.to_yaml).to eql @test_data["Output"]["SecurityRules"].to_yaml
    end
  end

  before (:context) do
    Context.component.set_variables("nlb", { "NLBArn" => "MyNLBArn" })
    correct_input = Marshal.load(Marshal.dump(@test_data['Input']['initialize']['correct']))
    @aws_vpc_endpoint_service = AwsVPCEndpointService.new('correct', correct_input)
  end

  context '.name_records' do
    it 'return name records' do
      expect(@aws_vpc_endpoint_service.name_records).to be_a(Hash)
    end
  end

  context '.deploy' do
    it 'deploys with new function stack successfully' do
      allow(@aws_vpc_endpoint_service).to receive(:_update_security_rules)
      allow(Defaults).to receive(:component_stack_name).and_return('dummy-stack-name')
      allow(AwsHelper).to receive(:cfn_create_stack).and_return(
        'StackId' => 'dummy-stack-id',
        'StackName' => 'dummy-stack-name'
      )
      expect { @aws_vpc_endpoint_service.deploy }.not_to raise_error
    end

    it 'deploys with new function stack successfully' do
      allow(@aws_vpc_endpoint_service).to receive(:_update_security_rules)
      allow(Defaults).to receive(:component_stack_name).and_return('dummy-stack-name')
      allow(AwsHelper).to receive(:cfn_create_stack).and_return(
        'StackId' => 'dummy-stack-id',
        'StackName' => 'dummy-stack-name'
      )
      expect { @aws_vpc_endpoint_service.deploy }.not_to raise_error
    end

    it 'raise on error' do
      allow(@aws_vpc_endpoint_service).to receive(:_update_security_rules)
      allow(Defaults).to receive(:component_stack_name).and_return('dummy-stack-name')
      allow(AwsHelper).to receive(:cfn_create_stack).and_raise(ActionError)
      expect { @aws_vpc_endpoint_service.deploy }.to raise_error(/Failed to create stack/)
    end
  end

  context '._full_template' do
    it 'generate template' do
      template = @aws_vpc_endpoint_service.send(:_full_template)
      expect(template).to eq(@test_data["Output"]["_full_template"])
    end
  end

  context '.release' do
    it 'successfully executes release' do
      expect { @aws_vpc_endpoint_service.release } .not_to raise_error
    end
  end

  context '.teardown' do
    it 'successfully executes teardown' do
      allow(Context).to receive_message_chain('component.stack_id').and_return('dummy-stack-id')
      allow(AwsHelper).to receive(:cfn_delete_stack).and_return(nil)
      allow(@aws_vpc_endpoint_service).to receive(:_clean_ad_deployment_dns_record)
      allow(@aws_vpc_endpoint_service).to receive(:_clean_ad_release_dns_record)
      expect { @aws_vpc_endpoint_service.teardown }.not_to raise_error
    end

    it 'fails to delete stack due to cfn exception' do
      allow(Context).to receive_message_chain('component.stack_id').and_return('dummy-stack-id')
      allow(AwsHelper).to receive(:cfn_delete_stack).and_raise(RuntimeError)
      allow(@aws_vpc_endpoint_service).to receive(:_clean_ad_deployment_dns_record)
      allow(@aws_vpc_endpoint_service).to receive(:_clean_ad_release_dns_record)
      expect { @aws_vpc_endpoint_service.teardown }.to raise_exception(RuntimeError)
    end
  end
end # RSpec.describe
