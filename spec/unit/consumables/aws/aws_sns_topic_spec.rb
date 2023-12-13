require 'consumables/aws/aws_sns_topic'
require 'consumables/aws/builders/sns_topic_builder'
require 'util/nsupdate'

RSpec.describe AwsSnsTopic do
  before(:context) do
    test_data_file = "#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"
    @test_data = YAML.load_file(
      test_data_file,
      permitted_classes: ['IamSecurityRule']
    )['UnitTest']
  end

  context '.initialize' do
    it 'initialize without error' do
      expect { AwsSnsTopic.new 'correct', @test_data['Input']['initialize']['correct'] }.not_to raise_exception
    end

    it 'fail initialize with error - multiple' do
      expect { AwsSnsTopic.new 'multiple', @test_data['Input']['initialize']['multiple'] }
        .to raise_error(RuntimeError, /This component does not support multiple/)
    end

    it 'fail initialize with error - wrong-type' do
      expect { AwsSnsTopic.new 'wrong-type', @test_data['Input']['initialize']['wrong-type'] }
        .to raise_error(RuntimeError, /is not supported by this component/)
    end

    it 'fail initialize with error - nil' do
      expect { AwsSnsTopic.new 'nil', @test_data['Input']['initialize']['nil'] }
        .to raise_error(RuntimeError, /Must specify a type for resource/)
    end
  end

  context '.security_rules' do
    it 'returns security rules' do
      sns_topic = AwsSnsTopic.new 'correct', @test_data['Input']['initialize']['correct']
      allow(Context).to receive_message_chain('component.variable').and_return('dummy-arn')
      security_rules = sns_topic.security_rules
      expect(security_rules).to eq @test_data['Output']['security_rules']
    end
  end

  context '.security_items' do
    it 'returns security items' do
      sns_topic = AwsSnsTopic.new 'correct', @test_data['Input']['initialize']['correct']
      security_items = sns_topic.security_items
      expect(security_items).to eq []
    end
  end

  before (:context) do
    @sns_topic = AwsSnsTopic.new 'correct', @test_data['Input']['initialize']['correct']
  end

  context '.deploy' do
    it 'deploys with new function stack successfully' do
      allow(Defaults).to receive(:component_stack_name)
      allow(@sns_topic).to receive(:_build_template)
      allow(Context).to receive_message_chain('component.set_variables')

      allow(@sns_topic).to receive(:_update_security_rules)

      # Mock creation of a stack
      allow(AwsHelper).to receive(:cfn_create_stack).and_return(
        'StackId' => 'dummy-stack-id',
        'StackName' => 'dummy-stack-name'
      )
      allow(Context).to receive_message_chain('component.set_variables')

      allow(@sns_topic).to receive(:deploy_ad_dns_records)

      allow(Context).to receive_message_chain('component.variable')
      expect { @sns_topic.deploy }.not_to raise_error
    end

    it 'fails with Failed to create stack' do
      allow(Defaults).to receive(:component_stack_name)
      allow(@sns_topic).to receive(:_build_template)
      allow(Context).to receive_message_chain('component.set_variables')

      allow(@sns_topic).to receive(:_update_security_rules)
      allow(Context).to receive_message_chain('component.variable')

      # Mock creation of a stack
      allow(AwsHelper).to receive(:cfn_create_stack).and_raise(StandardError)

      expect { @sns_topic.deploy }.to raise_exception /Failed to create stack/
    end

    it 'deploys with Failed to deploy DNS records' do
      allow(Defaults).to receive(:component_stack_name)
      allow(@sns_topic).to receive(:_build_template)
      allow(Context).to receive_message_chain('component.set_variables')

      allow(@sns_topic).to receive(:_update_security_rules)

      # Mock creation of a stack
      allow(AwsHelper).to receive(:cfn_create_stack).and_return(
        'StackId' => 'dummy-stack-id',
        'StackName' => 'dummy-stack-name'
      )
      allow(Context).to receive_message_chain('component.set_variables')
      allow(Defaults).to receive(:ad_dns_zone?).and_return(true)
      allow(@sns_topic).to receive(:deploy_ad_dns_records).and_raise(StandardError)
      allow(Context).to receive_message_chain('component.variable')
      expect { @sns_topic.deploy }.to raise_exception /Failed to deploy DNS records/
    end
  end

  before (:context) do
    @sns_topic = AwsSnsTopic.new 'correct', @test_data['Input']['initialize']['correct']
  end

  context '.release' do
    it 'success' do
      expect { @sns_topic.release } .not_to raise_error
    end
  end

  before (:context) do
    @sns_topic = AwsSnsTopic.new 'correct', @test_data['Input']['initialize']['correct']
  end

  context '.teardown' do
    it 'seccessfully executes teardown' do
      allow(Context).to receive_message_chain('component.stack_id').and_return('dummy-stack-id')
      allow(AwsHelper).to receive(:cfn_delete_stack).and_return(nil)

      allow(@sns_topic).to receive(:_clean_ad_deployment_dns_record)
      allow(@sns_topic).to receive(:_clean_ad_release_dns_record)

      expect { @sns_topic.teardown }.not_to raise_error
    end

    it 'fails with - Failed to delete stack' do
      allow(Context).to receive_message_chain('component.stack_id').and_return('dummy-stack-id')
      allow(AwsHelper).to receive(:cfn_delete_stack).and_raise(RuntimeError)

      allow(@sns_topic).to receive(:_clean_ad_deployment_dns_record)
      allow(@sns_topic).to receive(:_clean_ad_release_dns_record)

      expect { @sns_topic.teardown }.to raise_exception(RuntimeError)
    end

    it 'fails with - Failed to remove AD DNS records during teardown' do
      allow(Context).to receive_message_chain('component.stack_id').and_return('dummy-stack-id')
      allow(AwsHelper).to receive(:cfn_delete_stack).and_return(nil)

      allow(@sns_topic).to receive(:_clean_ad_deployment_dns_record)
      allow(@sns_topic).to receive(:_clean_ad_release_dns_record).and_raise(RuntimeError)
      expect(Log).to receive(:warn).with(/Failed to remove the release AD DNS records during teardown/)

      expect { @sns_topic.teardown }.to raise_exception(RuntimeError)
    end

    it 'fails with - Failed to remove the deployment AD DNS records during teardown' do
      allow(Context).to receive_message_chain('component.stack_id').and_return('dummy-stack-id')
      allow(AwsHelper).to receive(:cfn_delete_stack).and_return(nil)

      allow(@sns_topic).to receive(:_clean_ad_deployment_dns_record).and_raise(RuntimeError)
      allow(@sns_topic).to receive(:_clean_ad_release_dns_record)
      expect(Log).to receive(:warn).with(/Failed to remove the deployment AD DNS records during teardown/)

      expect { @sns_topic.teardown }.to raise_exception(RuntimeError)
    end
  end

  context '._build_template' do
    it 'successfully executes' do
      sns_topic = AwsSnsTopic.new('sns_topic', @test_data['Input']['_full_template']['Valid'])

      allow(Context).to receive_message_chain('environment.account_id').and_return('dummy-source-account')
      allow(Context).to receive_message_chain('environment.variable')
        .with('sns_source_accounts', [])
        .and_return(['dummy-account-1', 'dummy-account-2'])

      allow(Context).to receive_message_chain('environment.variable')
        .with('dns_zone', "qcpaws.qantas.com.au")
        .and_return(['qcpaws.qantas.com.au'])
      allow(Defaults).to receive(:ad_dns_zone?).and_return(false)
      allow(sns_topic).to receive(:_process_deploy_r53_dns_records)
      expect(sns_topic.send(:_build_template)).to eq @test_data['Output']['_full_template']
    end
  end

  context '.name_records' do
    it 'successfully executes' do
      sns_topic = AwsSnsTopic.new('sns_topic', @test_data['Input']['_full_template']['Valid'])
      expect { sns_topic.send(:name_records) }.not_to raise_exception
    end
  end
end # RSpec.describe
