$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws")
require 'aws_kinesis'
require 'builders/kinesis_stream_builder'

RSpec.describe AwsKinesis do
  before(:context) do
    test_data_file = "#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"
    @test_data = YAML.load_file(
      test_data_file,
      permitted_classes: ['IamSecurityRule']
    )['UnitTest']
  end

  context '.initialize' do
    it 'initialize without error' do
      expect { AwsKinesis.new 'correct', @test_data['Input']['initialize']['correct'] }.not_to raise_exception
    end

    it 'fail initialize with error - multiple' do
      expect { AwsKinesis.new 'multiple', @test_data['Input']['initialize']['multiple'] }
        .to raise_error(RuntimeError, /This component does not support multiple/)
    end

    it 'fail initialize with error - wrong-type' do
      expect { AwsKinesis.new 'wrong-type', @test_data['Input']['initialize']['wrong-type'] }
        .to raise_error(RuntimeError, /is not supported by this component/)
    end

    it 'fail initialize with error - nil' do
      expect { AwsKinesis.new 'nil', @test_data['Input']['initialize']['nil'] }
        .to raise_error(RuntimeError, /Must specify a type for resource/)
    end

    it 'fail initialize with error - bad reteion' do
      expect { AwsKinesis.new 'nil', @test_data['Input']['initialize']['wrong_retention'] }
        .to raise_error(RuntimeError, /Pipeline::RetentionPeriod must be between 24 hours and 168 hours/)
    end
  end

  context '.security_rules' do
    it 'returns security rules' do
      aws_kinesis = AwsKinesis.new 'correct', @test_data['Input']['initialize']['correct']
      allow(Context).to receive_message_chain('component.variable').and_return('dummy-arn')
      allow(Context).to receive_message_chain('kms.secrets_key_arn').and_return('dummy-kms-arn')
      security_rules = aws_kinesis.security_rules
      expect(security_rules).to eq @test_data['Output']['security_rules']
    end
  end

  context '.security_items' do
    it 'returns security rules' do
      aws_kinesis = AwsKinesis.new 'correct', @test_data['Input']['initialize']['correct']
      security_items = aws_kinesis.security_items
      expect(security_items).to eq @test_data['Output']['security_items']
    end
  end

  before (:context) do
    @aws_kinesis = AwsKinesis.new 'correct', @test_data['Input']['initialize']['correct']
  end

  context '.deploy' do
    it 'deploys with new function stack successfully' do
      allow(Defaults).to receive(:component_stack_name)
      allow(@aws_kinesis).to receive(:_build_template)
      allow(Context).to receive_message_chain('component.set_variables')

      allow(@aws_kinesis).to receive(:_update_security_rules)

      # Mock creation of a stack
      allow(AwsHelper).to receive(:cfn_create_stack).and_return(
        'StackId' => 'dummy-stack-id',
        'StackName' => 'dummy-stack-name'
      )
      allow(Context).to receive_message_chain('component.set_variables')

      allow(Context).to receive_message_chain('component.variable')
      allow(AwsHelper).to receive(:kinesis_set_retention_period_hours)
      allow(@aws_kinesis).to receive(:deploy_ad_dns_records)

      expect { @aws_kinesis.deploy }.not_to raise_error
    end

    it 'fails with Failed to create stack' do
      allow(Defaults).to receive(:component_stack_name)
      allow(@aws_kinesis).to receive(:_build_template)
      allow(Context).to receive_message_chain('component.set_variables')

      allow(@aws_kinesis).to receive(:_update_security_rules)
      allow(Context).to receive_message_chain('component.variable')

      # Mock creation of a stack
      allow(AwsHelper).to receive(:cfn_create_stack).and_raise(StandardError)

      expect { @aws_kinesis.deploy }.to raise_exception /Failed to create stack/
    end

    it 'deploys with Failed to deploy DNS records' do
      allow(Defaults).to receive(:component_stack_name)
      allow(@aws_kinesis).to receive(:_build_template)
      allow(Context).to receive_message_chain('component.set_variables')

      allow(@aws_kinesis).to receive(:_update_security_rules)

      # Mock creation of a stack
      allow(AwsHelper).to receive(:cfn_create_stack).and_return(
        'StackId' => 'dummy-stack-id',
        'StackName' => 'dummy-stack-name'
      )
      allow(Context).to receive_message_chain('component.set_variables')

      allow(Context).to receive_message_chain('component.variable')
      allow(AwsHelper).to receive(:kinesis_set_retention_period_hours)
      allow(@aws_kinesis).to receive(:deploy_ad_dns_records).and_raise(StandardError)

      expect { @aws_kinesis.deploy }.to raise_exception /Failed to deploy DNS records/
    end
  end

  before (:context) do
    @aws_kinesis = AwsKinesis.new 'correct', @test_data['Input']['initialize']['correct']
  end

  context '.release' do
    it 'success' do
      expect { @aws_kinesis.release } .not_to raise_error
    end
  end

  before (:context) do
    @aws_kinesis = AwsKinesis.new 'correct', @test_data['Input']['initialize']['correct']
  end

  context '.teardown' do
    it 'seccessfully executes teardown' do
      allow(Context).to receive_message_chain('component.stack_id').and_return('dummy-stack-id')
      allow(AwsHelper).to receive(:cfn_delete_stack).and_return(nil)

      allow(@aws_kinesis).to receive(:_clean_ad_deployment_dns_record)
      allow(@aws_kinesis).to receive(:_clean_ad_release_dns_record)

      expect { @aws_kinesis.teardown }.not_to raise_error
    end

    it 'fails with - Failed to delete stack' do
      allow(Context).to receive_message_chain('component.stack_id').and_return('dummy-stack-id')
      allow(AwsHelper).to receive(:cfn_delete_stack).and_raise(RuntimeError)

      allow(@aws_kinesis).to receive(:_clean_ad_deployment_dns_record)
      allow(@aws_kinesis).to receive(:_clean_ad_release_dns_record)

      expect { @aws_kinesis.teardown }.to raise_exception(RuntimeError)
    end

    it 'fails with - Failed to remove AD DNS records during teardown' do
      allow(Context).to receive_message_chain('component.stack_id').and_return('dummy-stack-id')
      allow(AwsHelper).to receive(:cfn_delete_stack).and_return(nil)

      allow(@aws_kinesis).to receive(:_clean_ad_deployment_dns_record)
      allow(@aws_kinesis).to receive(:_clean_ad_release_dns_record).and_raise(RuntimeError)
      expect(Log).to receive(:warn).with(/Failed to remove AD DNS records during teardown/)

      expect { @aws_kinesis.teardown }.to raise_exception(RuntimeError)
    end
  end

  context '._build_template' do
    it 'successfully executes' do
      aws_kinesis = AwsKinesis.new('kinesis', @test_data['Input']['_full_template']['Valid'])

      allow(Context).to receive_message_chain('kms.secrets_key_arn')
        .and_return('arn:aws:kms:ap-southeast-2:111122223333:key/1234abcd-12ab-34cd-56ef-1234567890ab')

      allow(Context).to receive_message_chain('environment.account_id').and_return('dummy-source-account')
      allow(Context).to receive_message_chain('environment.variable')
        .with('log_destination_source_accounts', [])
        .and_return(['dummy-account-1', 'dummy-account-2'])

      allow(Context).to receive_message_chain('environment.variable')
        .with('dns_zone', "qcpaws.qantas.com.au")
        .and_return(['qcpaws.qantas.com.au'])
      allow(Defaults).to receive(:r53_dns_zone?).and_return(true)
      allow(aws_kinesis).to receive(:_process_deploy_r53_dns_records)

      expect(aws_kinesis.send(:_build_template)).to eq @test_data['Output']['_full_template']
    end

    it 'successfully executes with custom key' do
      aws_kinesis = AwsKinesis.new('kinesis', @test_data['Input']['_full_template_stream_encryption']['Valid'])

      allow(Context).to receive_message_chain('environment.account_id').and_return('dummy-source-account')
      allow(Context).to receive_message_chain('environment.variable')
        .with('log_destination_source_accounts', [])
        .and_return(['dummy-account-1', 'dummy-account-2'])

      allow(Context).to receive_message_chain('environment.variable')
        .with('dns_zone', "qcpaws.qantas.com.au")
        .and_return(['qcpaws.qantas.com.au'])

      allow(Defaults).to receive(:r53_dns_zone?).and_return(true)
      allow(aws_kinesis).to receive(:_process_deploy_r53_dns_records)

      expect(aws_kinesis.send(:_build_template)).to eq @test_data['Output']['_full_template_stream_encryption']
    end
  end

  context '.name_records' do
    it 'successfully executes' do
      aws_kinesis = AwsKinesis.new('kinesis', @test_data['Input']['_full_template']['Valid'])
      expect { aws_kinesis.send(:name_records) }.not_to raise_exception
    end
  end

  context '._clean_ad_release_dns_record' do
    it 'successfully executes _clean_ad_release_dns_record' do
      allow(Context).to receive_message_chain('component.variable').and_return('test.deploydns.ams01.qcp')
      allow(Util::Nsupdate).to receive(:delete_dns_record)
      aws_kinesis = AwsKinesis.new('kinesis', @test_data['Input']['_full_template']['Valid'])
      expect { aws_kinesis.send(:_clean_ad_release_dns_record, 'kinesis') }.not_to raise_exception
    end

    it 'failed to executes _clean_ad_release_dns_record' do
      allow(Context).to receive_message_chain('component.variable').and_return('test.deploydns.ams01.qcp')
      allow(Util::Nsupdate).to receive(:delete_dns_record).and_raise(RuntimeError)
      aws_kinesis = AwsKinesis.new('kinesis', @test_data['Input']['_full_template']['Valid'])
      expect {
        aws_kinesis.send(:_clean_ad_release_dns_record, 'kinesis')
      }.to raise_exception(RuntimeError, /Failed to delete release DNS record/)
    end

    it 'Dont execute delete_dns_record method if release_dns_name is nil ' do
      allow(Defaults).to receive(:release_dns_name).and_return(nil)
      allow(Util::Nsupdate).to receive(:delete_dns_record)
      aws_kinesis = AwsKinesis.new('kinesis', @test_data['Input']['_full_template']['Valid'])
      expect { aws_kinesis.send(:_clean_ad_release_dns_record, 'kinesis') }.not_to raise_exception
    end

    it ' Skip clean up if no release build number _clean_ad_release_dns_record' do
      allow(Context).to receive_message_chain('persist.released_build?').and_return(false)
      allow(Context).to receive_message_chain('persist.released_build_number').and_return(false)
      allow(Util::Nsupdate).to receive(:delete_dns_record)
      aws_kinesis = AwsKinesis.new('kinesis', @test_data['Input']['_full_template']['Valid'])
      expect { aws_kinesis.send(:_clean_ad_release_dns_record, 'kinesis') }.not_to raise_exception
    end
  end

  context '._clean_ad_deployment_dns_record' do
    it 'successfully executes _clean_ad_deployment_dns_record' do
      allow(Context).to receive_message_chain('component.variable').and_return('test.deploydns.ams01.qcp')
      allow(Util::Nsupdate).to receive(:delete_dns_record)
      aws_kinesis = AwsKinesis.new('kinesis', @test_data['Input']['_full_template']['Valid'])
      expect { aws_kinesis.send(:_clean_ad_deployment_dns_record, 'kinesis') }.not_to raise_exception
    end

    it 'failed to executes _clean_ad_deployment_dns_record' do
      allow(Context).to receive_message_chain('component.variable').and_return('test.deploydns.ams01.qcp')
      allow(Util::Nsupdate).to receive(:delete_dns_record).and_raise(RuntimeError)
      aws_kinesis = AwsKinesis.new('kinesis', @test_data['Input']['_full_template']['Valid'])
      expect { aws_kinesis.send(:_clean_ad_deployment_dns_record, 'kinesis') }.to raise_error /Failed to delete deployment DNS record/
    end

    it 'Dont execute delete_dns_record method _clean_ad_deployment_dns_record' do
      allow(Defaults).to receive(:deployment_dns_name).and_return(nil)
      aws_kinesis = AwsKinesis.new('kinesis', @test_data['Input']['_full_template']['Valid'])
      expect { aws_kinesis.send(:_clean_ad_deployment_dns_record, 'kinesis') }.not_to raise_exception
    end

    it ' Skip clean up of records unless AD dns zone _clean_ad_deployment_dns_record' do
      allow(Defaults).to receive(:ad_dns_zone?).and_return(false)
      aws_kinesis = AwsKinesis.new('kinesis', @test_data['Input']['_full_template']['Valid'])
      expect { aws_kinesis.send(:_clean_ad_deployment_dns_record, 'kinesis') }.not_to raise_exception
    end
  end

  context '.create_ad_release_dns_records' do
    it 'successfully executes create_ad_release_dns_records' do
      allow(Context).to receive_message_chain('component.variable').and_return('kinesis-arn')
      allow(Util::Nsupdate).to receive(:create_dns_record)
      aws_kinesis = AwsKinesis.new('kinesis', @test_data['Input']['_full_template']['Valid'])
      expect { aws_kinesis.send(:create_ad_release_dns_records, component_name: 'test') }.not_to raise_error
    end
  end

  context '.deploy_ad_dns_records' do
    it 'successfully executes deploy_ad_dns_records' do
      allow(Context).to receive_message_chain('component.variable').and_return('kinesis-arn')
      allow(Util::Nsupdate).to receive(:create_dns_record)
      aws_kinesis = AwsKinesis.new('kinesis', @test_data['Input']['_full_template']['Valid'])
      expect { aws_kinesis.send(:deploy_ad_dns_records) }.not_to raise_error
    end
  end

  context '._process_deploy_r53_dns_records' do
    it 'successfully executes private host r53 zone _process_deploy_r53_dns_records' do
      template = @test_data['Input']['process_release_r53_dns_record']
      allow(Context).to receive_message_chain('component.variable').and_return('test.deploydns.ams01.qcp')
      aws_kinesis = AwsKinesis.new('kinesis', @test_data['Input']['_full_template']['Valid'])
      allow(aws_kinesis).to receive(:_process_route53_records)
      expect { aws_kinesis.send(:_process_deploy_r53_dns_records, template: template) }.not_to raise_error
    end
  end

  context '.process_release_r53_dns_record' do
    it 'successfully executes private host r53 zone' do
      template = @test_data['Input']['process_release_r53_dns_record']
      allow(Defaults).to receive_message_chain('dns_zone').and_return('ams.qcp')
      allow(Context).to receive_message_chain('component.variable').and_return('test.deploydns.ams01.qcp')
      aws_kinesis = AwsKinesis.new('kinesis', @test_data['Input']['_full_template']['Valid'])
      allow(aws_kinesis).to receive(:_process_route53_records)
      expect { aws_kinesis.send(:process_release_r53_dns_record, template: template, zone: 'ams01.qcp', component_name: 'test') }.not_to raise_error
    end

    it 'successfully executes public host r53 zone' do
      template = @test_data['Input']['initialize']['correct']
      allow(Log).to receive(:output).and_call_original
      allow(Defaults).to receive_message_chain('dns_zone').and_return('public.ams.qcp')
      allow(Context).to receive_message_chain('component.variable').and_return('test.master-01.nonp.c031-01.ams01.public.ams.qcp')
      aws_kinesis = AwsKinesis.new('kinesis', @test_data['Input']['_full_template']['Valid'])
      allow(aws_kinesis).to receive(:_process_route53_records)
      expect(Log).to receive(:output).with("kinesis DNS: kinesis.master.dev.c031-99.ams01.nonp.public.ams.qcp")
      expect(Log).to receive(:output).with("kinesis DNS: kinesis-logcollector.master.dev.c031-99.ams01.nonp.public.ams.qcp")
      aws_kinesis.send(:process_release_r53_dns_record, template: template, zone: 'public.ams.qcp', component_name: 'kinesis')
    end
  end
end # RSpec.describe
