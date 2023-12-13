$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws")
require 'aws_alb'
require 'yaml'

RSpec.describe AwsAlb do
  before(:context) do
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))['IntegrationTest']
    @component_name = @test_data['Input']['ComponentName']

    Context.component.set_variables('TestComponent', {
      'BuildNumber' => '1',
      'DeployDnsName' => 'deploy-dns-name.domain.com',
      'ReleaseDnsName' => 'release-dns-name.domain.com',
    })
  end

  context '.initialize' do
    it 'raises exception if resource type is unsupported' do
      expect {
        AwsAlb.new(
          @component_name,
          @test_data["Input"]["Invalid"]["UnsupportedResourceType"]
        )
      }.to raise_error(RuntimeError, /Resource type ([a-zA-Z:"]*) is not supported by this component/)
    end

    it 'raises exception if resource type is nil' do
      expect {
        AwsAlb.new(@component_name, @test_data["Input"]["Invalid"]["NilResourceType"])
      }.to raise_exception(RuntimeError, /Must specify a type for resource/)
    end
  end

  context '.name_records' do
    it 'successfully executes' do
      aws_component = AwsAlb.new(@component_name, @test_data['Input']['Valid'])
      name_records = aws_component.name_records

      expect(name_records['DeployDnsName']).not_to eq(nil)
      expect(name_records['ReleaseDnsName']).not_to eq(nil)
    end

    it 'successfully return custom dns record sets' do
      aws_component = AwsAlb.new(@component_name, @test_data['Input']['ValidWithWildcard-qcpaws'])
      name_records = aws_component.name_records

      expect(name_records['DeployDnsName']).not_to eq(nil)
      expect(name_records['ReleaseDnsName']).not_to eq(nil)
      expect(name_records['CustomDeployDnsName']).not_to eq(nil)
      expect(name_records['CustomReleaseDnsName']).not_to eq(nil)
    end
  end

  context '.deploy' do
    it 'deploys stack' do
      component = AwsAlb.new(@component_name, @test_data['Input']['Valid'])

      allow(component).to receive(:_template)
      allow(AwsHelper).to receive(:cfn_create_stack)
      allow(component).to receive(:deploy_ad_dns_records)
      allow(Context).to receive_message_chain('component.set_variables')
      allow(Context).to receive_message_chain('component.variable')

      expect { component.deploy }.not_to raise_exception
    end
  end

  context '.teardown' do
    it 'delete stack' do
      component = AwsAlb.new(@component_name, @test_data['Input']['Valid'])

      allow(AwsHelper).to receive(:cfn_delete_stack)
      expect { component.teardown }.not_to raise_exception
    end
  end

  context '._template' do
    it 'returns cloudformation template' do
      allow(Defaults).to receive(:ad_dns_zone?)
      allow(Defaults).to receive(:r53_dns_zone?).and_return(true)
      allow(Context).to receive_message_chain('environment.variable')
        .with('dns_zone', "qcpaws.qantas.com.au")
        .and_return('qcpaws.qantas.com.au')
      allow(Context).to receive_message_chain("environment.vpc_id").and_return('vpc-123')
      allow(Context).to receive_message_chain("environment.subnet_ids").and_return(['subnet-123'])
      allow(Context).to receive_message_chain("environment.persist_override").and_return('false')
      allow(Context).to receive_message_chain('component.sg_id').and_return('sg-123')
      allow(Context).to receive_message_chain('asir.destination_sg_id').and_return('sg-456')
      allow(Context).to receive_message_chain('component.replace_variables')

      component = AwsAlb.new(@component_name, @test_data['Input']['Valid'])

      result_template = component.send :_template

      # This DeployDns should be covered in the name_records
      expect(result_template['Resources']['DeployDns']).not_to eq(nil)
      result_template['Resources'].delete('DeployDns')

      expect(result_template['Resources']).to eq @test_data['Output']['_template']['Resources']
    end
  end
end
