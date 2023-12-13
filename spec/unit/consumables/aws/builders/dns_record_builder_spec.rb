$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws/builders")
require "dns_record_builder"
require "route53_record_builder"

RSpec.describe DnsRecordBuilder do
  before(:context) do
    @dummy_class = DummyClass.new
    @dummy_class.extend(DnsRecordBuilder)
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))['UnitTest']
  end
  context '.process_release_r53_dns_record' do
    it 'successfully executes private host r53 zone' do
      template = @test_data['Input']['process_release_r53_dns_record']
      allow(Context).to receive_message_chain('component.variable').and_return('test.deploydns.ams01.qcp')
      allow(@dummy_class).to receive(:_process_route53_records)

      expect {
        @dummy_class.process_release_r53_dns_record(
          template: template,
          zone: 'ams01.qcp',
          component_name: 'test'
        )
      }.not_to raise_error
    end

    it 'successfully executes public host r53 zone' do
      template = @test_data['Input']['process_release_r53_dns_record']
      allow(Context).to receive_message_chain('component.variable').and_return('test.deploydns.ams01.qcp')
      allow(@dummy_class).to receive(:_process_route53_records)

      expect {
        @dummy_class.process_release_r53_dns_record(
          template: template,
          zone: 'qcpa.qantas.com.au',
          component_name: 'test'
        )
      }.not_to raise_error
    end
  end

  context '._process_deploy_r53_dns_records' do
    it 'successfully executes private host r53 zone _process_deploy_r53_dns_records' do
      template = @test_data['Input']['process_release_r53_dns_record']
      allow(Context).to receive_message_chain('component.variable').and_return('test.deploydns.ams01.qcp')
      allow(@dummy_class).to receive(:_process_route53_records)

      expect {
        @dummy_class._process_deploy_r53_dns_records(
          template: template,
          zone: 'ams01.qcp',
          resource_records: ['Fn::GetAtt' => ['DNSName']],
          component_name: 'test'
        )
      }.not_to raise_error
    end

    it 'successfully executes public host r53 zone _process_deploy_r53_dns_records' do
      template = @test_data['Input']['process_release_r53_dns_record']
      allow(Context).to receive_message_chain('component.variable').and_return('test.deploydns.ams01.qcp')
      allow(@dummy_class).to receive(:_process_route53_records)

      expect {
        @dummy_class._process_deploy_r53_dns_records(
          template: template,
          zone: 'qcpa.qantas.com.au',
          resource_records: ['Fn::GetAtt' => ['DNSName']],
          component_name: 'test'
        )
      }.not_to raise_error
    end
  end

  context '.deploy_ad_dns_records' do
    it 'successfully executes deploy_ad_dns_records' do
      allow(Util::Nsupdate).to receive(:create_dns_record)
      expect {
        @dummy_class.deploy_ad_dns_records(
          dns_name: 'test.dev-01.dev.c031-01.ams01.nonp.qcpaws.qantas.com.au',
          endpoint: 'loadbalance',
          type: 'CNAME'
        )
      }.not_to raise_error
    end

    it 'successfully executes custom dns deploy_ad_dns_records' do
      allow(Util::Nsupdate).to receive(:create_dns_record)
      allow(Context).to receive_message_chain('component.variable').and_return('true')
      Context.component.variable
      expect {
        @dummy_class.deploy_ad_dns_records(
          dns_name: 'test.dev-01.dev.c031-01.ams01.nonp.qcpaws.qantas.com.au',
          endpoint: 'loadbalance',
          type: 'CNAME'
        )
      }.not_to raise_error
    end

    it 'fail if the dns record exceeds the limit' do
      allow(Util::Nsupdate).to receive(:create_dns_record)
      allow(Context).to receive_message_chain('component.variable').and_return('true')
      Context.component.variable
      expect {
        @dummy_class.deploy_ad_dns_records(
          dns_name: 'testcomponentname-resourcename.big-branchname-01.dev.c031-01.ams01.nonp.qcpaws.qantas.com.au',
          endpoint: 'loadbalance',
          type: 'CNAME'
        )
      }.to raise_error /The Custom DNS record testcomponentname-resourcename-big-branchname-01-dev-c031-01-ams01-nonp.qcpaws.qantas.com.au exceeds the max character limit of 63.Please use small branch name or component name/
    end
  end

  context '.create_ad_release_dns_records' do
    it 'successfully executes create_ad_release_dns_records' do
      allow(Context).to receive_message_chain('component.variable').and_return('test.deploydns.ams01.qcp')
      allow(Util::Nsupdate).to receive(:create_dns_record)
      allow(Context).to receive_message_chain('component.variable').with('test', 'WildcardCertifiateIsUsed', nil).and_return(nil)
      expect {
        @dummy_class.create_ad_release_dns_records(
          component_name: 'test'
        )
      }.not_to raise_error
    end
    it 'successfully executes custom dns create_ad_release_dns_records' do
      allow(Context).to receive_message_chain('component.variable').and_return('test.master-01.dev.c031-99.ams01.nonp.qcpaws.qantas.com.au')
      allow(Util::Nsupdate).to receive(:create_dns_record)
      allow(Context).to receive_message_chain('component.variable').with('test', 'WildcardCertifiateIsUsed', nil).and_return('true')
      Context.component.variable
      expect {
        @dummy_class.create_ad_release_dns_records(
          component_name: 'test'
        )
      }.not_to raise_error
    end

    it 'fail if the dns record exceeds the limit' do
      allow(Defaults).to receive_message_chain('release_dns_name').and_return('testcomponentname-resourcename.big-branchname.dev.c031-01.ams01.nonp.qcpaws.qantas.com.au')
      allow(Context).to receive_message_chain('component.variable').and_return('testcomponentname-resourcename.big-branchname-01.dev.c031-01.ams01.nonp.qcpaws.qantas.com.au')
      allow(Util::Nsupdate).to receive(:create_dns_record)
      allow(Context).to receive_message_chain('component.variable').with('test', 'WildcardCertifiateIsUsed', nil).and_return('true')
      Context.component.variable
      expect {
        @dummy_class.create_ad_release_dns_records(
          component_name: 'test',
        )
      }.to raise_error /The Custom DNS record testcomponentname-resourcename-big-branchname-dev-c031-01-ams01-nonp.qcpaws.qantas.com.au exceeds the max character limit of 63.Please use small branch name or component name/
    end
  end

  context '._clean_ad_deployment_dns_record' do
    it 'successfully executes _clean_ad_deployment_dns_record' do
      allow(Context).to receive_message_chain('component.variable').and_return('test.deploydns.ams01.qcp')
      allow(Util::Nsupdate).to receive(:delete_dns_record)
      expect { @dummy_class._clean_ad_deployment_dns_record('test') }.not_to raise_error
    end

    it 'failed to executes _clean_ad_deployment_dns_record' do
      allow(Context).to receive_message_chain('component.variable').and_return('test.deploydns.ams01.qcp')
      allow(Util::Nsupdate).to receive(:delete_dns_record).and_raise(RuntimeError)
      expect { @dummy_class._clean_ad_deployment_dns_record('test') }.to raise_error /Failed to delete deployment DNS record/
    end

    it 'Dont execute delete_dns_record method _clean_ad_deployment_dns_record' do
      allow(Defaults).to receive(:deployment_dns_name).and_return(nil)
      allow(Defaults).to receive(:custom_dns_name).and_return(nil)
      expect { @dummy_class._clean_ad_deployment_dns_record('test') }.not_to raise_error
    end

    it ' Skip clean up of records unless AD dns zone _clean_ad_deployment_dns_record' do
      allow(Defaults).to receive(:ad_dns_zone?).and_return(false)
      expect { @dummy_class._clean_ad_deployment_dns_record('test') }.not_to raise_error
    end

    it 'successfully clean the custom dns _clean_ad_deployment_dns_record' do
      allow(Util::Nsupdate).to receive(:delete_dns_record)
      allow(Context).to receive_message_chain('component.variable').and_return('true')
      Context.component.variable
      expect {
        @dummy_class._clean_ad_deployment_dns_record('test')
      }.not_to raise_error
    end

    it 'fail to clean if the dns record exceeds the limit' do
      allow(Defaults).to receive_message_chain('deployment_dns_name').and_return('testcomponentname-resourcename.big-branchname-02.dev.c031-01.ams01.nonp.qcpaws.qantas.com.au')
      allow(Util::Nsupdate).to receive(:delete_dns_record)
      allow(Context).to receive_message_chain('component.variable').and_return('true')
      Context.component.variable
      expect {
        @dummy_class._clean_ad_deployment_dns_record('test')
      }.to raise_error /The Custom DNS record testcomponentname-resourcename-big-branchname-02-dev-c031-01-ams01-nonp.qcpaws.qantas.com.au exceeds the max character limit of 63.Please use small branch name or component name/
    end
  end

  context '._clean_ad_release_dns_record' do
    it 'successfully executes _clean_ad_release_dns_record' do
      allow(Context).to receive_message_chain('component.variable').and_return('test.deploydns.ams01.qcp')
      allow(Util::Nsupdate).to receive(:delete_dns_record)
      expect { @dummy_class._clean_ad_release_dns_record('test') }.not_to raise_error
    end

    it 'failed to executes _clean_ad_release_dns_record' do
      allow(Context).to receive_message_chain('component.variable').and_return('test.deploydns.ams01.qcp')
      allow(Util::Nsupdate).to receive(:delete_dns_record).and_raise(RuntimeError)
      expect { @dummy_class._clean_ad_release_dns_record('test') }.to raise_error /Failed to delete release DNS record/
    end

    it 'Dont execute delete_dns_record method _clean_ad_release_dns_record' do
      allow(Defaults).to receive(:release_dns_name).and_return(nil)
      expect { @dummy_class._clean_ad_release_dns_record('test') }.not_to raise_error
    end

    it ' Skip clean up if no release build number _clean_ad_release_dns_record' do
      allow(Context).to receive_message_chain('persist.released_build?').and_return(false)
      allow(Context).to receive_message_chain('persist.released_build_number').and_return(false)
      expect { @dummy_class._clean_ad_release_dns_record('test') }.not_to raise_error
    end

    it 'successfully clean the custom dns _clean_ad_release_dns_record' do
      allow(Util::Nsupdate).to receive(:delete_dns_record)
      allow(Context).to receive_message_chain('component.variable').and_return('true')
      Context.component.variable
      expect {
        @dummy_class._clean_ad_release_dns_record('test')
      }.not_to raise_error
    end

    it 'fail to clean if the dns record exceeds the limit' do
      allow(Defaults).to receive_message_chain('release_dns_name').and_return('testcomponentname-resourcename.big-branchname.dev.c031-01.ams01.nonp.qcpaws.qantas.com.au')
      allow(Util::Nsupdate).to receive(:delete_dns_record)
      allow(Context).to receive_message_chain('component.variable').and_return('true')
      Context.component.variable
      expect {
        @dummy_class._clean_ad_release_dns_record('test')
      }.to raise_error /The Custom DNS record testcomponentname-resourcename-big-branchname-dev-c031-01-ams01-nonp.qcpaws.qantas.com.au exceeds the max character limit of 63.Please use small branch name or component name/
    end
  end

  context '.custom_name_records' do
    it 'successfully executes' do
      input = @test_data['Input']['Valid']
      name_records = @dummy_class.custom_name_records(component_name: 'Test', content: input, pattern: '@wildcard-qcpaws')

      expect(name_records['DeployDnsName']).not_to eq(nil)
      expect(name_records['ReleaseDnsName']).not_to eq(nil)
    end

    it 'successfully return custom dns record sets' do
      input = @test_data['Input']['ValidWithWildcard-qcpaws']
      name_records = @dummy_class.custom_name_records(component_name: 'Test', content: input, pattern: '@wildcard-qcpaws')

      expect(name_records['DeployDnsName']).not_to eq(nil)
      expect(name_records['ReleaseDnsName']).not_to eq(nil)
      expect(name_records['CustomDeployDnsName']).not_to eq(nil)
      expect(name_records['CustomReleaseDnsName']).not_to eq(nil)
    end
  end
end
