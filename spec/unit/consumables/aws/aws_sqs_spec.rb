$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib/consumables/aws"))
require 'aws_sqs'

RSpec.describe AwsSqs do
  include_examples "shared context"

  before(:context) do
    @test_data = YAML.load_file("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml")['UnitTest']
  end

  context '.initialize' do
    it 'initialize without error' do
      expect { AwsSqs.new 'correct', @test_data['Input']['initialize']['correct'] }.not_to raise_exception
    end

    it 'fail initialize with error - multiple' do
      expect { AwsSqs.new 'multiple', @test_data['Input']['initialize']['multiple'] }
        .to raise_error(RuntimeError, /This component does not support multiple/)
    end

    it 'fail initialize with error - wrong-type' do
      expect { AwsSqs.new 'wrong-type', @test_data['Input']['initialize']['wrong-type'] }
        .to raise_error(RuntimeError, /is not supported by this component/)
    end

    it 'fail initialize with error - nil' do
      expect { AwsSqs.new 'nil', @test_data['Input']['initialize']['nil'] }
        .to raise_error(RuntimeError, /Must specify a type for resource/)
    end
  end

  context '.security_rules' do
    it 'returns security rules' do
      aws_sqs = AwsSqs.new 'correct', @test_data['Input']['initialize']['correct']
      allow(Context).to receive_message_chain('component.variable').and_return('dummy-arn')
      security_rules = aws_sqs.security_rules

      expect(security_rules).to eq ([])
    end
  end

  context '.security_items' do
    it 'returns security rules' do
      aws_sqs = AwsSqs.new 'correct', @test_data['Input']['initialize']['correct']
      security_items = aws_sqs.security_items
      expect(security_items).to eq([])
    end
  end

  before (:context) do
    @aws_sqs = AwsSqs.new 'correct', @test_data['Input']['initialize']['correct']
  end

  context '.deploy' do
    it 'deploys with new function stack successfully' do
      allow(Defaults).to receive(:component_stack_name)
      allow(@aws_sqs).to receive(:_build_template)
      allow(Context).to receive_message_chain('component.set_variables')

      allow(@aws_sqs).to receive(:_update_security_rules)

      # Mock creation of a stack
      allow(AwsHelper).to receive(:cfn_create_stack).and_return(
        'StackId' => 'dummy-stack-id',
        'StackName' => 'dummy-stack-name'
      )
      allow(Context).to receive_message_chain('component.set_variables')

      allow(Context).to receive_message_chain('component.variable')
      allow(@aws_sqs).to receive(:deploy_ad_dns_records)

      expect { @aws_sqs.deploy }.not_to raise_error
    end

    it 'fails with Failed to create stack' do
      allow(Defaults).to receive(:component_stack_name)
      allow(@aws_sqs).to receive(:_build_template)
      allow(Context).to receive_message_chain('component.set_variables')

      allow(@aws_sqs).to receive(:_update_security_rules)

      # Mock creation of a stack
      allow(AwsHelper).to receive(:cfn_create_stack).and_raise(StandardError)

      expect { @aws_sqs.deploy }.to raise_exception /Failed to create stack/
    end

    it 'fails to deploy DNS records' do
      allow(Defaults).to receive(:component_stack_name)
      allow(@aws_sqs).to receive(:_build_template)
      allow(Context).to receive_message_chain('component.set_variables')

      allow(@aws_sqs).to receive(:_update_security_rules)

      # Mock creation of a stack
      allow(AwsHelper).to receive(:cfn_create_stack).and_return(
        'StackId' => 'dummy-stack-id',
        'StackName' => 'dummy-stack-name'
      )
      allow(Context).to receive_message_chain('component.set_variables')

      allow(Context).to receive_message_chain('component.variable')
      allow(@aws_sqs).to receive(:deploy_ad_dns_records).and_raise(StandardError)

      expect { @aws_sqs.deploy }.to raise_exception /Failed to deploy DNS records/
    end
  end

  context '._build_template' do
    it 'generates default / customised templates for AD Dns zone' do
      valid_component_name = "SQS"
      allow(Defaults).to receive(:dns_zone).and_return(Defaults.ad_dns_zone)

      awsSqs = AwsSqs.new(valid_component_name, @test_data['Input']['_build_template']['Minimal'])
      expect(awsSqs.send :_build_template).to eq(@test_data['Output']['_build_template']['Minimal']['Default'])

      awsSqs = AwsSqs.new(valid_component_name, @test_data['Input']['_build_template']['Customised'])
      expect(awsSqs.send :_build_template).to eq(@test_data['Output']['_build_template']['Customised']['Default'])
    end

    it 'generates default / customised templates for Route53 Dns zone' do
      valid_component_name = "SQS"
      allow(Defaults).to receive(:dns_zone).and_return(Defaults.r53_dns_zone)

      awsSqs = AwsSqs.new(valid_component_name, @test_data['Input']['_build_template']['Minimal'])
      expect(awsSqs.send :_build_template).to eq(@test_data['Output']['_build_template']['Minimal']['Route53'])

      awsSqs = AwsSqs.new(valid_component_name, @test_data['Input']['_build_template']['Customised'])
      expect(awsSqs.send :_build_template).to eq(@test_data['Output']['_build_template']['Customised']['Route53'])
    end
  end

  before (:context) do
    @aws_sqs = AwsSqs.new 'correct', @test_data['Input']['initialize']['correct']
  end

  context '.release' do
    it 'success' do
      expect { @aws_sqs.release } .not_to raise_error
    end
  end

  before (:context) do
    @aws_sqs = AwsSqs.new 'correct', @test_data['Input']['initialize']['correct']
  end

  context '.teardown' do
    it 'seccessfully executes teardown' do
      allow(Context).to receive_message_chain('component.stack_id').and_return('dummy-stack-id')
      allow(AwsHelper).to receive(:cfn_delete_stack).and_return(nil)

      allow(@aws_sqs).to receive(:_clean_ad_deployment_dns_record)
      allow(@aws_sqs).to receive(:_clean_ad_release_dns_record)

      expect { @aws_sqs.teardown }.not_to raise_error
    end

    it 'fails to delete stack' do
      allow(Context).to receive_message_chain('component.stack_id').and_return('dummy-stack-id')
      allow(AwsHelper).to receive(:cfn_delete_stack).and_raise(StandardError)

      allow(@aws_sqs).to receive(:_clean_ad_deployment_dns_record)
      allow(@aws_sqs).to receive(:_clean_ad_release_dns_record)

      expect { @aws_sqs.teardown }.to raise_exception(StandardError)
    end

    it 'fails to delete stack' do
      allow(Context).to receive_message_chain('component.stack_id').and_return('dummy-stack-id')
      allow(AwsHelper).to receive(:cfn_delete_stack).and_raise(StandardError)

      allow(@aws_sqs).to receive(:_clean_ad_deployment_dns_record)
      allow(@aws_sqs).to receive(:_clean_ad_release_dns_record).and_raise(StandardError)

      expect { @aws_sqs.teardown }.to raise_exception(StandardError)
    end
  end
end # RSpec.describe
