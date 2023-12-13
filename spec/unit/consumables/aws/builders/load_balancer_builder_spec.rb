$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws/builders")
require 'load_balancer_builder'

RSpec.describe LoadBalancerBuilder do
  before(:context) do
    @dummy_class = DummyClass.new
    @dummy_class.extend(LoadBalancerBuilder)
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))
  end

  context '._process_load_balancer' do
    it 'updates template when valid inputs are passed on' do
      @test_data['UnitTest']['Input']['Configurations'].each_with_index do |configuration, index|
        template = @test_data['UnitTest']['Input']['Template']
        load_balancer = {}
        security_group_ids = ['sg-123', 'sg-456']

        configuration.each do |name, resource|
          load_balancer[name] = resource if resource['Type'] == 'AWS::ElasticLoadBalancing::LoadBalancer'
        end

        allow(Context).to receive_message_chain("environment.subnet_ids").and_return(["subnet-123", "subnet-456"])
        allow(Context).to receive_message_chain("environment.account_id").and_return('678567898989')
        allow(Defaults).to receive("nonp_wildcard_qcpaws_certificate_name").and_return('wildcard-qcpaws.qantas.com.au')
        expect {
          @dummy_class._process_load_balancer(
            template: template,
            load_balancer_definition: load_balancer,
            security_group_ids: security_group_ids
          )
        }.not_to raise_error

        expect(template).to eq @test_data['UnitTest']['Output']['_process_load_balancer'][index]
      end
    end
  end
  context '._process_listeners' do
    it 'successfully replacing nonp wildcard alias' do
      test_data = [{ "LoadBalancerPort" => "80", "InstancePort" => "80", "Protocol" => "HTTP" }, { "LoadBalancerPort" => "80", "InstancePort" => "80", "Protocol" => "HTTP", "SSLCertificateId" => "@wildcard-qcpaws" }]
      expected = [{ "LoadBalancerPort" => "80", "InstancePort" => "80", "Protocol" => "HTTP" }, { "LoadBalancerPort" => "80", "InstancePort" => "80", "Protocol" => "HTTP", "SSLCertificateId" => "{{resolve:ssm:/qcp/acm_certificate_arn}}" }]

      allow(Context).to receive_message_chain("environment.account_id").and_return('678567898989')
      allow(Defaults).to receive("nonp_wildcard_qcpaws_certificate_name").and_return('wildcard-qcpaws.qantas.com.au')
      expect(
        @dummy_class._process_listeners(
          listeners: test_data
        )
      ).to eq(expected)
    end
    it 'successfully replacing prod wildcard alias' do
      test_data = [{ "LoadBalancerPort" => "80", "InstancePort" => "80", "Protocol" => "HTTP" }, { "LoadBalancerPort" => "80", "InstancePort" => "80", "Protocol" => "HTTP", "SSLCertificateId" => "@wildcard-qcpaws" }]
      expected = [{ "LoadBalancerPort" => "80", "InstancePort" => "80", "Protocol" => "HTTP" }, { "LoadBalancerPort" => "80", "InstancePort" => "80", "Protocol" => "HTTP", "SSLCertificateId" => "{{resolve:ssm:/qcp/acm_certificate_arn}}" }]

      allow(Defaults).to receive("sections").and_return({ env: 'prod' })
      allow(Context).to receive_message_chain("environment.account_id").and_return('2453890890')
      allow(Defaults).to receive("prod_wildcard_qcpaws_certificate_name").and_return('wildcard-qcpaws.qantas.com.au')
      expect(
        @dummy_class._process_listeners(
          listeners: test_data
        )
      ).to eq(expected)
    end
    it 'raise exception if wrong alias specified for nonp ' do
      test_data = [{ "LoadBalancerPort" => "80", "InstancePort" => "80", "Protocol" => "HTTP" }, { "LoadBalancerPort" => "80", "InstancePort" => "80", "Protocol" => "HTTP", "SSLCertificateId" => "@wildcard-qcpaws-test" }]

      allow(Context).to receive_message_chain("environment.account_id").and_return('678567898989')
      allow(Defaults).to receive("nonp_wildcard_qcpaws_certificate_name").and_return('wildcard-qcpaws.qantas.com.au')
      expect {
        @dummy_class._process_listeners(
          listeners: test_data
        )
      }.to raise_exception /Wrong alias value @wildcard-qcpaws-test is specified for SSLCertificateId property/
    end

    it 'testing no alias value' do
      test_data = [{ "LoadBalancerPort" => "80", "InstancePort" => "80", "Protocol" => "HTTP" }, { "LoadBalancerPort" => "80", "InstancePort" => "80", "Protocol" => "HTTP", "SSLCertificateId" => "arn:aws:iam::678567898989:server-certificate/wildcard-qcpaws.qantas.com.au" }]
      expected = [{ "LoadBalancerPort" => "80", "InstancePort" => "80", "Protocol" => "HTTP" }, { "LoadBalancerPort" => "80", "InstancePort" => "80", "Protocol" => "HTTP", "SSLCertificateId" => "arn:aws:iam::678567898989:server-certificate/wildcard-qcpaws.qantas.com.au" }]

      expect(
        @dummy_class._process_listeners(
          listeners: test_data
        )
      ).to eq(expected)
    end
  end
end # RSpec.describe
