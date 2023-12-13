$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws")
require 'aws_amq'
require 'yaml'

RSpec.describe AwsAmq do
  before(:context) do
    @test_data = YAML.load(
      File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"),
      permitted_classes: ['IpSecurityRule', 'IpPort', 'IamSecurityRule']
    )['UnitTest']

    @component_name = @test_data['Input']['ComponentName']

    Context.component.set_variables('TestComponent', {
      'BuildNumber' => '1',
      'DeployDnsName' => 'deploy-dns-name.domain.com',
      'ReleaseDnsName' => 'release-dns-name.domain.com',
    })
  end

  context '.initialize' do
    it 'successfully initialize AMQ' do
      expect {
        @test_data['Input']["Valid"].each do |key, value|
          AwsAmq.new(@component_name, value)
        end
      }.not_to raise_error
    end

    it 'raises exception if resource name is invalid' do
      expect {
        AwsAmq.new(
          @component_name,
          @test_data["Input"]["Invalid"]["WrongResource"]
        )
      }.to raise_error(RuntimeError, /Invalid resource name/)
    end

    it 'raises exception if multiple amq brokers are defined' do
      expect {
        AwsAmq.new(
          @component_name,
          @test_data["Input"]["Invalid"]["MultipleAMQDefinition"]
        )
      }.to raise_error(RuntimeError, /component does not support multiple/)
    end

    it 'raises exception if resource type is unsupported' do
      expect {
        AwsAmq.new(
          @component_name,
          @test_data["Input"]["Invalid"]["UnsupportedResourceType"]
        )
      }.to raise_error(RuntimeError, /Resource type ([a-zA-Z:"]*) is not supported by this component/)
    end

    it 'raises exception if resource type is not provide' do
      expect {
        AwsAmq.new(@component_name,  @test_data["Input"]["Invalid"]["InvalidNilType"])
      }.to raise_exception(RuntimeError, /Resource type ([a-zA-Z:"]*) is not supported by this component/)
    end

    it 'raises exception if resource type is nil' do
      expect {
        AwsAmq.new(@component_name,  @test_data["Input"]["Invalid"]["NilResourceType"])
      }.to raise_exception(RuntimeError, /Must specify a type for resource/)
    end
  end

  context '.name_record' do
    it 'successfully returns DeployDns for single instance broker' do
      awsAmq = AwsAmq.new(@component_name, @test_data['Input']['Valid']['SingleInstanceBroker'])
      name_records = awsAmq.name_records

      expect(name_records['AMQPrimaryDeployDnsName']).not_to eq(nil)
      expect(name_records['AMQPrimaryReleaseDnsName']).not_to eq(nil)
    end

    it 'successfully returns DeployDns for Multi AZ Broker' do
      awsAmq = AwsAmq.new(@component_name, @test_data['Input']['Valid']['Broker'])
      name_records = awsAmq.name_records

      expect(name_records['AMQPrimaryDeployDnsName']).not_to eq(nil)
      expect(name_records['AMQPrimaryReleaseDnsName']).not_to eq(nil)
      expect(name_records['AMQSecondaryDeployDnsName']).not_to eq(nil)
      expect(name_records['AMQSecondaryReleaseDnsName']).not_to eq(nil)
    end
  end

  context '.security_items' do
    it 'create security groups' do
      @test_data["Input"]["Valid"].each do |key, value|
        aws_amq = AwsAmq.new(@component_name, value)
        expect(aws_amq.security_items).to eql @test_data["TestResult"]["SecurityItems"]
      end
    end
  end

  context '.security_rules' do
    it 'returns security rules for component definition of Broker' do
      aws_amq = AwsAmq.new(
        @component_name,
        @test_data['Input']['Valid']['BrokerwithSecurityRules']
      )
      allow(Context).to receive_message_chain('component.variable').and_return('broker-arn')

      expect(aws_amq.security_rules.to_yaml).to eql @test_data["TestResult"]["SecurityRules"].to_yaml
    end
    it 'should fail if correct source is not provided' do
      aws_amq = AwsAmq.new(@component_name, @test_data['Input']['Invalid']['UnspportedSourceSecurityRules'])

      allow(Context).to receive_message_chain('component.variable').and_return('broker-arn')
      expect { aws_amq.security_rules }.to raise_exception(RuntimeError, /Could not determine security rule type from source/)
    end

    it 'should return empty array if key security is not mentioned in the component definition' do
      aws_amq = AwsAmq.new(@component_name, @test_data['Input']['Valid']['BrokerwithoutSecurityRules'])

      # security_rules = aws_amq.security_rules
      # expect (security_rules).to be_empty
      expect { aws_amq.security_rules }.not_to raise_error
    end
  end

  context '.deploy' do
    it 'AMQ Broker deployed successfully' do
      aws_amq = AwsAmq.new(@component_name, @test_data['Input']['Valid']['Broker'])

      allow(aws_amq).to receive(:_validate_amq_password)

      allow(Defaults).to receive(:component_stack_name).and_return('dummy-stack-name')
      allow(Defaults).to receive(:get_tags).and_return([])
      allow(aws_amq).to receive(:_build_amq_configuration_template).and_return({ 'Resources' => {}, 'Outputs' => {} })

      allow(aws_amq).to receive(:_build_broker_template).and_return({ 'Resources' => {}, 'Outputs' => {} })
      allow(Context).to receive_message_chain('component.set_variables')
      allow(Context).to receive_message_chain('component.variable').and_return('config-arn')
      allow(aws_amq).to receive(:_process_amq_template_parameters)
      allow(AwsHelper).to receive(:cfn_create_stack)
      allow(AwsHelper).to receive(:apply_amq_tags)
      allow(AwsHelper).to receive(:cfn_update_stack)
      allow(AwsHelper).to receive(:cfn_stack_exists).and_return('dummy-function-stack-id')
      allow(Defaults).to receive(:ad_dns_zone?)
      expect { aws_amq.deploy }.not_to raise_error
    end

    it 'AMQ Broker deploy - stack_id updated in stack_outputs' do
      aws_amq = AwsAmq.new(@component_name, @test_data['Input']['Valid']['Broker'])

      allow(aws_amq).to receive(:_validate_amq_password)

      allow(Defaults).to receive(:component_stack_name).and_return('dummy-stack-name')
      allow(Defaults).to receive(:get_tags).and_return([])
      allow(aws_amq).to receive(:_build_amq_configuration_template).and_return({ 'Resources' => {}, 'Outputs' => {} })

      allow(aws_amq).to receive(:_build_broker_template).and_return({ 'Resources' => {}, 'Outputs' => {} })
      allow(Context).to receive_message_chain('component.set_variables')
      allow(Context).to receive_message_chain('component.variable').and_return('config-arn')
      allow(aws_amq).to receive(:_process_amq_template_parameters)
      allow(AwsHelper).to receive(:cfn_create_stack).and_return({ 'StackId' => 'dummy-stack' })
      allow(AwsHelper).to receive(:apply_amq_tags)
      allow(AwsHelper).to receive(:cfn_update_stack)
      allow(AwsHelper).to receive(:cfn_stack_exists).and_return('dummy-function-stack-id')
      allow(Defaults).to receive(:ad_dns_zone?)
      expect { aws_amq.deploy }.not_to raise_error
    end

    it 'AMQ Broke deployment failed with Runtime Error' do
      aws_amq = AwsAmq.new(@component_name, @test_data['Input']['Valid']['Broker'])

      allow(aws_amq).to receive(:_validate_amq_password)

      allow(Defaults).to receive(:component_stack_name).and_return('dummy-stack-name')
      allow(Context).to receive_message_chain('component.variable').and_return('config-arn')
      allow(Defaults).to receive(:get_tags).and_return([])
      allow(AwsHelper).to receive(:cfn_update_stack)
      allow(AwsHelper).to receive(:cfn_stack_exists).and_return('dummy-function-stack-id')
      allow(aws_amq).to receive(:_build_broker_template).and_return({ 'Resources' => {}, 'Outputs' => {} })
      allow(aws_amq).to receive(:_build_amq_configuration_template).and_return({ 'Resources' => {}, 'Outputs' => {} })
      allow(AwsHelper).to receive(:cfn_update_stack)
      allow(AwsHelper).to receive(:cfn_stack_exists).and_return('dummy-function-stack-id')
      allow(AwsHelper).to receive(:apply_amq_tags)
      allow(Context).to receive_message_chain('component.set_variables')
      allow(aws_amq).to receive(:_process_amq_template_parameters)
      allow(AwsHelper).to receive(:cfn_create_stack).and_raise(RuntimeError)
      allow(Defaults).to receive(:ad_dns_zone?)
      expect { aws_amq.deploy }.to raise_exception RuntimeError
    end

    it 'AMQ Broker deployment fails to create DNS record' do
      aws_amq = AwsAmq.new(@component_name, @test_data['Input']['Valid']['Broker'])

      allow(aws_amq).to receive(:_validate_amq_password)

      allow(Defaults).to receive(:component_stack_name).and_return('dummy-stack-name')
      allow(Defaults).to receive(:get_tags).and_return([])
      allow(aws_amq).to receive(:_build_amq_configuration_template).and_return({ 'Resources' => {}, 'Outputs' => {} })
      allow(AwsHelper).to receive(:cfn_update_stack)
      allow(AwsHelper).to receive(:cfn_stack_exists).and_return('dummy-function-stack-id')
      allow(aws_amq).to receive(:_build_broker_template).and_return({ 'Resources' => {}, 'Outputs' => {} })
      allow(Context).to receive_message_chain('component.set_variables')
      allow(Context).to receive_message_chain('component.variable').and_return('config-arn')
      allow(AwsHelper).to receive(:apply_amq_tags)
      allow(aws_amq).to receive(:_process_amq_template_parameters)
      allow(aws_amq).to receive(:deploy_amq_ad_dns_records).and_raise(RuntimeError)
      allow(AwsHelper).to receive(:cfn_create_stack)
      expect { aws_amq.deploy }.to raise_exception /Failed to deploy DNS records/
    end

    it 'should create new AMQ Configuration' do
      aws_amq = AwsAmq.new(@component_name, @test_data['Input']['Valid']['Broker'])

      allow(aws_amq).to receive(:_validate_amq_password)

      allow(Defaults).to receive(:component_stack_name).and_return('dummy-stack-name')
      allow(Defaults).to receive(:get_tags).and_return([])
      allow(aws_amq).to receive(:_build_amq_configuration_template).and_return({ 'Resources' => {}, 'Outputs' => {} })
      allow(AwsHelper).to receive(:cfn_stack_exists).and_return(nil)
      allow(AwsHelper).to receive(:cfn_create_stack)
      allow(aws_amq).to receive(:_build_broker_template).and_return({ 'Resources' => {}, 'Outputs' => {} })
      allow(Context).to receive_message_chain('component.set_variables')
      allow(Context).to receive_message_chain('component.variable').and_return('config-arn')
      allow(AwsHelper).to receive(:apply_amq_tags)
      allow(aws_amq).to receive(:_process_amq_template_parameters)
      allow(aws_amq).to receive(:deploy_amq_ad_dns_records)
      allow(AwsHelper).to receive(:cfn_create_stack)
      expect { aws_amq.deploy }.not_to raise_error
    end

    it 'should fail if create stack failed' do
      aws_amq = AwsAmq.new(@component_name, @test_data['Input']['Valid']['Broker'])

      allow(aws_amq).to receive(:_validate_amq_password)

      allow(Defaults).to receive(:component_stack_name).and_return('dummy-stack-name')
      allow(Defaults).to receive(:get_tags).and_return([])
      allow(aws_amq).to receive(:_build_amq_configuration_template).and_return({ 'Resources' => {}, 'Outputs' => {} })
      allow(AwsHelper).to receive(:cfn_stack_exists).and_return(nil)
      allow(AwsHelper).to receive(:cfn_create_stack)
      allow(aws_amq).to receive(:_build_broker_template).and_return({ 'Resources' => {}, 'Outputs' => {} })
      allow(Context).to receive_message_chain('component.set_variables')
      allow(Context).to receive_message_chain('component.variable').and_return('config-arn')
      allow(AwsHelper).to receive(:apply_amq_tags)
      allow(aws_amq).to receive(:_process_amq_template_parameters)
      allow(aws_amq).to receive(:deploy_amq_ad_dns_records)
      allow(AwsHelper).to receive(:cfn_create_stack).and_raise(RuntimeError)
      expect { aws_amq.deploy }.to raise_error(RuntimeError)
    end
  end

  context '.release' do
    it 'AMQ Broker released successfully' do
      aws_amq = AwsAmq.new(@component_name, @test_data['Input']['Valid']['Broker'])

      allow(Util::Nsupdate).to receive(:create_dns_record)
      allow(Defaults).to receive_messages(:release_dns_name => 2)
      allow(Context).to receive_message_chain('component.variable').and_return('dns-2')
      expect { aws_amq.release }.not_to raise_error
    end
  end

  context '.teardown' do
    it 'deletes stack and dns record' do
      allow(AwsHelper).to receive(:s3_get_object)
      allow(Context).to receive_message_chain('component.stack_id').and_return('dummy-stack')
      allow(AwsHelper).to receive(:cfn_delete_stack)

      @test_data["Input"]["Valid"].each do |key, value|
        aws_amq = AwsAmq.new(@component_name, value)

        allow(Util::Nsupdate).to receive_messages(:delete_dns_record => 1)
        allow(Context).to receive_message_chain('component.variable').and_return('dummy-stack')
        expect { aws_amq.teardown }.not_to raise_error
        expect { aws_amq.teardown }.not_to raise_error
      end
    end

    it 'should raise error if stack deletion fails' do
      allow(Context).to receive_message_chain('component.stack_id').and_return('dummy-stack-id')
      allow(AwsHelper).to receive(:cfn_delete_stack).and_raise(RuntimeError)

      aws_amq = AwsAmq.new(@component_name, @test_data["Input"]["Valid"]['Broker'])
      allow(Context).to receive_message_chain('component.variable').and_return('dummy-stack')
      allow(aws_amq).to receive(:_clean_amq_ad_deployment_dns_record)
      allow(aws_amq).to receive(:_clean_amq_ad_release_dns_record)
      expect { aws_amq.teardown }.to raise_exception(RuntimeError)
    end

    it 'should raise exception if delete deploy dns fails' do
      allow(Context).to receive_message_chain('component.stack_id').and_return('dummy-stack-id')
      allow(AwsHelper).to receive(:cfn_delete_stack)

      aws_amq = AwsAmq.new(@component_name, @test_data["Input"]["Valid"]['Broker'])
      allow(Context).to receive_message_chain('component.variable').and_return('dummy-stack')
      allow(aws_amq).to receive(:_clean_amq_ad_deployment_dns_record).and_raise(RuntimeError)
      allow(aws_amq).to receive(:_clean_amq_ad_release_dns_record)
      expect { aws_amq.teardown }.to raise_exception(RuntimeError)
    end

    it 'should raise exception if delete release dns fails' do
      allow(Context).to receive_message_chain('component.stack_id').and_return('dummy-stack-id')
      allow(AwsHelper).to receive(:cfn_delete_stack)
      allow(Context).to receive_message_chain('component.variable').and_return('dummy-stack')
      aws_amq = AwsAmq.new(@component_name, @test_data["Input"]["Valid"]['Broker'])

      allow(aws_amq).to receive(:_clean_amq_ad_deployment_dns_record)
      allow(aws_amq).to receive(:_clean_amq_ad_release_dns_record).and_raise(RuntimeError)
      expect { aws_amq.teardown }.to raise_exception(RuntimeError)
    end

    it 'should teardown last build of the branch' do
      allow(AwsHelper).to receive(:s3_get_object)
      allow(Context).to receive_message_chain('component.stack_id').and_return('dummy-stack')
      allow(AwsHelper).to receive(:cfn_delete_stack)
      allow(Context).to receive_message_chain('persist.released_build_number').and_return('dummy-stack')
      allow(Context).to receive_message_chain('persist.released_build?').and_return(nil)
      @test_data["Input"]["Valid"].each do |key, value|
        aws_amq = AwsAmq.new(@component_name, value)

        allow(Util::Nsupdate).to receive_messages(:delete_dns_record => 1)
        allow(Context).to receive_message_chain('component.variable').and_return('dummy-stack')
        expect { aws_amq.teardown }.not_to raise_error
        expect { aws_amq.teardown }.not_to raise_error
      end
    end
  end

  context '.deploy_amq_ad_dns_records' do
    it 'Should return amq ad dns record for multi az instance' do
      allow(Context).to receive_message_chain('component.variable').and_return('broker-endpoint')
      allow(Util::Nsupdate).to receive(:create_dns_record)
      aws_amq = AwsAmq.new(@component_name, @test_data['Input']['Valid']['Broker'])
      expect { aws_amq.send(:deploy_amq_ad_dns_records) }.not_to raise_error
    end
    it 'Should return amq ad dns record for single instance' do
      allow(Context).to receive_message_chain('component.variable').and_return('broker-endpoint')
      allow(Util::Nsupdate).to receive(:create_dns_record)
      aws_amq = AwsAmq.new(@component_name, @test_data['Input']['Valid']['SingleInstanceBroker'])
      expect { aws_amq.send(:deploy_amq_ad_dns_records) }.not_to raise_error
    end
  end

  context '._build_broker_template' do
    it 'should build amq broker template successfully for Single Instance' do
      allow(Defaults).to receive(:dns_zone).and_return(Defaults.ad_dns_zone)
      allow(Context).to receive_message_chain("environment.vpc_id").and_return(['vpc-123'])
      allow(Context).to receive_message_chain("environment.subnet_ids").and_return(['subnet-123'])
      allow(Context).to receive_message_chain("environment.persist_override").and_return('false')
      allow(Context).to receive_message_chain("component.sg_id").and_return('sg-12345')
      allow(AwsHelper).to receive(:cfn_stack_exists).and_return('dummy-function-stack-id')
      allow(Context).to receive_message_chain('component.variable').and_return('amq-config-id')
      allow(Context).to receive_message_chain('component.replace_variables').and_return(@test_data['Input']['_build_template']['single_broker']['AMQ'])
      awsAmq = AwsAmq.new(@component_name, @test_data['Input']['_build_template']['single_broker'])
      allow(awsAmq).to receive(:_build_amq_configuration_template)
      allow(awsAmq).to receive_message_chain(:_process_amq_login)
      expect(awsAmq.send :_build_broker_template).to eq(@test_data['Output']['_build_template']['single_broker']['Default'])
    end

    it 'should build amq broker template successfully for Multi AZ' do
      allow(Defaults).to receive(:dns_zone).and_return(Defaults.ad_dns_zone)
      allow(Context).to receive_message_chain("environment.vpc_id").and_return(['vpc-123'])
      allow(Context).to receive_message_chain("environment.subnet_ids").and_return(['subnet-123', 'subnet-456'])
      allow(Context).to receive_message_chain("environment.persist_override").and_return('false')
      allow(Context).to receive_message_chain("component.sg_id").and_return('sg-12345')
      allow(AwsHelper).to receive(:cfn_stack_exists).and_return('dummy-function-stack-id')
      allow(Context).to receive_message_chain('component.variable').and_return('amq-config-id')
      allow(Context).to receive_message_chain('component.replace_variables').and_return(@test_data['Input']['_build_template']['multiAZ_broker']['AMQ'])
      awsAmq = AwsAmq.new(@component_name, @test_data['Input']['_build_template']['multiAZ_broker'])
      allow(awsAmq).to receive(:_build_amq_configuration_template)
      allow(awsAmq).to receive_message_chain(:_process_amq_login)
      expect(awsAmq.send :_build_broker_template).to eq(@test_data['Output']['_build_template']['multiAZ_broker']['Default'])
    end
  end

  context '._build_amq_configuration_template' do
    it 'should run successfully' do
      allow(Context).to receive_message_chain('component.replace_variables').and_return(@test_data['Input']['_build_template']['single_broker']['AMQConfiguration'])
      awsAmq = AwsAmq.new(@component_name, @test_data['Input']['_build_template']['single_broker'])
      expect(awsAmq.send :_build_amq_configuration_template)
    end

    it 'should build amq configuration template successfully' do
      allow(Context).to receive_message_chain('component.replace_variables').and_return(@test_data['Input']['_build_template']['single_broker']['AMQConfiguration'])
      awsAmq = AwsAmq.new(@component_name, @test_data['Input']['_build_template']['single_broker'])
      expect(awsAmq.send :_build_amq_configuration_template).to eq(@test_data['Output']['_build_template']['amq_configuration']['Default'])
    end
  end

  context '.create_ad_release_dns_records' do
    it 'successfully executes create_ad_release_dns_records for MultiAZ' do
      allow(Context).to receive_message_chain('component.variable').and_return('broker-endpoint')
      allow(Util::Nsupdate).to receive(:create_dns_record)
      aws_amq = AwsAmq.new(@component_name, @test_data['Input']['_build_template']['single_broker'])
      expect { aws_amq.send(:create_ad_release_dns_records, component_name: @component_name) }.not_to raise_error
    end

    it 'successfully executes create_ad_release_dns_records for single instance' do
      allow(Context).to receive_message_chain('component.variable').and_return('broker-endpoint')
      allow(Util::Nsupdate).to receive(:create_dns_record)
      aws_amq = AwsAmq.new(@component_name, @test_data['Input']['Valid']['Broker'])
      expect { aws_amq.send(:create_ad_release_dns_records, component_name: @component_name) }.not_to raise_error
    end
  end

  context '.deploy_amq_ad_dns_records' do
    it 'successfully executes deploy_amq_ad_dns_records for single instance' do
      allow(Context).to receive_message_chain('component.variable').and_return('broker-endpoint')
      allow(Util::Nsupdate).to receive(:create_dns_record)
      aws_amq = AwsAmq.new(@component_name, @test_data['Input']['_build_template']['single_broker'])
      expect { aws_amq.send(:deploy_amq_ad_dns_records) }.not_to raise_error
    end

    it 'Fails to delete DNS record if nsupdate has error' do
      allow(Context).to receive_message_chain('component.variable').and_return('broker-endpoint')
      allow(Util::Nsupdate).to receive(:create_dns_record).and_raise(RuntimeError)
      aws_amq = AwsAmq.new(@component_name, @test_data['Input']['_build_template']['single_broker'])
      expect { aws_amq.send(:deploy_amq_ad_dns_records) }.to raise_error(RuntimeError)
    end

    it 'successfully executes deploy_amq_ad_dns_records for MultiAZ instances' do
      allow(Context).to receive_message_chain('component.variable').and_return('broker-endpoint')
      allow(Util::Nsupdate).to receive(:create_dns_record)
      aws_amq = AwsAmq.new(@component_name, @test_data['Input']['Valid']['Broker'])
      expect { aws_amq.send(:deploy_amq_ad_dns_records) }.not_to raise_error
    end
  end

  context '._clean_amq_ad_deployment_dns_record' do
    it 'Deletes Deployed DNS' do
      allow(Context).to receive_message_chain('component.vairable').and_return('broker-endpoint')
      allow(Util::Nsupdate).to receive(:delete_dns_record)
      aws_amq = AwsAmq.new(@component_name, @test_data['Input']['Valid']['Broker'])
      expect { aws_amq.send(:_clean_amq_ad_deployment_dns_record) } .not_to raise_error
    end

    it 'raises exception while deleting DNS' do
      allow(Context).to receive_message_chain('component.vairable').and_return('broker-endpoint')
      allow(Defaults).to receive(:ad_dns_zone?).and_return(true)
      # allow(Defaults).to receive(:deployment_dns_name).and_return('dummy-stack-name')
      allow(Util::Nsupdate).to receive(:delete_dns_record).and_raise(ActionError)
      aws_amq = AwsAmq.new(@component_name, @test_data['Input']['Valid']['Broker'])
      expect { aws_amq.send(:_clean_amq_ad_deployment_dns_record).at_least(2) }.to raise_error(RuntimeError)
    end
  end

  context '._clean_amq_ad_release_dns_record' do
    it 'Deletes Released DNS' do
      allow(Context).to receive_message_chain('component.vairable').and_return('broker-endpoint')

      allow(Util::Nsupdate).to receive(:delete_dns_record)
      aws_amq = AwsAmq.new(@component_name, @test_data['Input']['Valid']['Broker'])
      expect { aws_amq.send(:_clean_amq_ad_release_dns_record).not_to raise_error }
    end

    it 'raises exception while deleting DNS record' do
      allow(Context).to receive_message_chain('component.variable').and_return('broker-endpoint')
      allow(Defaults).to receive(:release_dns_name).and_return('dummy-stack-name')
      allow(Util::Nsupdate).to receive(:delete_dns_record).and_raise(ActionError)
      aws_amq = AwsAmq.new(@component_name, @test_data['Input']['Valid']['Broker'])
      expect { aws_amq.send(:_clean_amq_ad_release_dns_record).at_least(2) }.to raise_error(RuntimeError)
    end
  end

  context '._validate_amq_password' do
    it 'Password in plain text error' do
      aws_amq = AwsAmq.new(@component_name, @test_data['Input']['Valid']['InvalidPassword'])
      allow(aws_amq).to receive(:_process_amq_admin_password)
      expect { aws_amq.send(:_validate_amq_password) }.to raise_error(ArgumentError, /AMQ Master Password can't be set as plaintext value/)
    end

    it 'Successfully creates AMQ password' do
      aws_amq = AwsAmq.new(@component_name, @test_data['Input']['Valid']['SingleInstanceBroker'])
      allow(aws_amq).to receive(:_process_amq_admin_password)
      expect { aws_amq.send(:_validate_amq_password) }.not_to raise_error
    end
  end

  context '._process_amq_template_parameters' do
    it 'can process amq template parameters' do
      allow(Context).to receive_message_chain('environment.persist_override')
      instance_name = "AMQ"

      allow(Context).to receive_message_chain('component.variable')
        .with(@component_name, instance_name + 'TestUserUsername', '')
        .and_return("TestUser")
      allow(Context).to receive_message_chain('component.variable')
        .with(@component_name, instance_name + 'TestUserPassword', '')
        .and_return("Test")

      aws_amq = AwsAmq.new(@component_name, @test_data['Input']['Valid']['SingleInstanceBroker'])

      aws_amq.instance_variable_set(:@template, { 'Parameters' => {
        instance_name + 'TestUserUsername' => {},
        instance_name + 'TestUserPassword' => {}
      } })
      aws_amq.send(:_process_amq_template_parameters)
    end

    it 'creates template parameter' do
      instance_name = "AMQ"

      test_results = [
        ['root', :undef],
        [nil, nil],
        [nil, 'pass'],
        ['root', nil],

        ['', ''],
        ['', 'pass'],
        ['root', ''],

        [:undef, :undef],
        [:undef, 'pass']
      ]

      allow(Context).to receive_message_chain('environment.persist_override')

      aws_amq = AwsAmq.new(@component_name, @test_data['Input']['Valid']['SingleInstanceBroker'])

      aws_amq.instance_variable_set(:@template, { 'Parameters' => {
        "AMQTestUserUsername" => {},
        "AMQTestUserPassword" => {}
      } })

      test_results.each do |results|
        Log.debug("_process_template_parameters: testing with [#{results}]")

        allow(Context).to receive_message_chain('component.variable')
          .with(@component_name, instance_name + "TestUserUsername", '')
          .and_return(results[0])
        allow(Context).to receive_message_chain('component.variable')
          .with(@component_name, instance_name + "TestUserPassword", '')
          .and_return(results[1])

        expect { aws_amq.send(:_process_amq_template_parameters) }.to raise_exception(RuntimeError, /Context variable (.+) is undefined, nil or empty/)
      end
    end
  end

  context '._amq_configuration_stack_name' do
    it 'returns AMQ Configuration name' do
      aws_amq = AwsAmq.new(@component_name, @test_data['Input']['Valid']['SingleInstanceBroker'])
      allow(Defaults).to receive(:sections).and_return(
        ams: 'ams01',
        qda: 'c031',
        build: 19,
        as: '01',
        ase: 'dev',
        branch: 'master'
      )
      amq_configuration_name = aws_amq.send(:_amq_configuration_stack_name)
      expect(amq_configuration_name).to eq('ams01-c031-01-dev-master-amq')
    end
  end

  context '.get_tags' do
    it 'returns the tags to be applied' do
      aws_amq = AwsAmq.new(@component_name, @test_data['Input']['Valid']['SingleInstanceBroker'])
      allow(Defaults).to receive(:sections).and_return(
        ams: 'ams01',
        qda: 'c031',
        build: 19,
        as: '01',
        ase: 'dev',
        branch: 'master',
        asbp_type: 'qda'
      )
      tag_details = aws_amq.get_tags(component_name: @component_name)
    end
  end
end
