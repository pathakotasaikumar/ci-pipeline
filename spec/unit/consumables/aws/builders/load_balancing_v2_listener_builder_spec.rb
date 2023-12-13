$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws/builders")
require 'load_balancing_v2_listener_builder'

RSpec.describe LoadBalancingV2ListenerBuilder do
  before(:context) do
    @dummy_class = DummyClass.new
    @dummy_class.extend(LoadBalancingV2ListenerBuilder)
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))
  end

  context '._process_load_balancer_v2_listener' do
    it 'updates template when valid inputs are passed on 1' do
      configuration = @test_data['UnitTest']['Input']['Configurations'][0]

      template = { 'Resources' => {}, 'Outputs' => {} }
      listener = {}

      configuration.each do |name, resource|
        next if resource['Type'] != 'AWS::ElasticLoadBalancingV2::Listener'

        listener[name] = resource
      end

      expect {
        @dummy_class._process_load_balancing_v2_listener(
          template: template,
          listener_definition: listener,
          load_balancer: 'dummy-load-balancer'
        )
      }.not_to raise_error

      expect(template).to eq @test_data['UnitTest']['Output']['_process_load_balancer_v2_listener'][0]
    end

    it 'updates template when valid inputs are passed on 2' do
      configuration = @test_data['UnitTest']['Input']['Configurations'][1]

      template = { 'Resources' => {}, 'Outputs' => {} }
      listener = {}

      configuration.each do |name, resource|
        next if resource['Type'] != 'AWS::ElasticLoadBalancingV2::Listener'

        listener[name] = resource
      end

      expect {
        @dummy_class._process_load_balancing_v2_listener(
          template: template,
          listener_definition: listener,
          load_balancer: { 'Ref' => 'dummy-load-balancer' }
        )
      }.not_to raise_error

      expect(template).to eq @test_data['UnitTest']['Output']['_process_load_balancer_v2_listener'][1]
    end
  end
  context '._process_certificates' do
    it 'successfully replacing nonp wildcard alias' do
      test_data = [{ "CertificateArn" => "@wildcard-qcpaws" }]
      expected = [{ "CertificateArn" => "{{resolve:ssm:/qcp/acm_certificate_arn}}" }]

      allow(Context).to receive_message_chain("environment.account_id").and_return('678567898989')
      allow(Defaults).to receive("nonp_wildcard_qcpaws_certificate_name").and_return('wildcard-qcpaws.qantas.com.au')
      expect(
        @dummy_class._process_certificates(
          certificates: test_data
        )
      ).to eq(expected)
    end
    it 'successfully replacing prod wildcard alias' do
      test_data = [{ "CertificateArn" => "@wildcard-qcpaws" }]
      expected = [{ "CertificateArn" => "{{resolve:ssm:/qcp/acm_certificate_arn}}" }]

      allow(Defaults).to receive("sections").and_return({ env: 'prod' })
      allow(Context).to receive_message_chain("environment.account_id").and_return('2453890890')
      allow(Defaults).to receive("prod_wildcard_qcpaws_certificate_name").and_return('wildcard-qcpaws.qantas.com.au')
      expect(
        @dummy_class._process_certificates(
          certificates: test_data
        )
      ).to eq(expected)
    end
    it 'raise exception if wrong alias specified for nonp ' do
      test_data = [{ "CertificateArn" => "@wildcard-qcpaws-tesst" }]

      allow(Context).to receive_message_chain("environment.account_id").and_return('678567898989')
      allow(Defaults).to receive("nonp_wildcard_qcpaws_certificate_name").and_return('wildcard-qcpaws.qantas.com.au')
      expect {
        @dummy_class._process_certificates(
          certificates: test_data
        )
      }.to raise_exception /Wrong alias value @wildcard-qcpaws-tesst is specified for CertificateArn property/
    end

    it 'testing no alias value' do
      test_data = [{ "CertificateArn" => "arn:aws:iam::678567898989:server-certificate/wildcard-qcpaws.qantas.com.au" }]
      expected = [{ "CertificateArn" => "arn:aws:iam::678567898989:server-certificate/wildcard-qcpaws.qantas.com.au" }]

      expect(
        @dummy_class._process_certificates(
          certificates: test_data
        )
      ).to eq(expected)
    end
  end
end # RSpec.describe
