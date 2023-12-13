$LOAD_PATH.unshift("#{BASE_DIR}/lib/util")
require 'os'

include Util::OS

RSpec.describe Defaults do
  before(:context) do
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))
  end

  context '.get_environment_from_plan_key' do
    it 'returns environment' do
      expect(Log).to receive(:warn).with(/Cannot determine environment from the plan key/)
      expect(Defaults.get_environment_from_plan_key("testing")).to eq("prod")
      expect(Defaults.get_environment_from_plan_key("CORE-C001S01DEV")).to eq("nonp")
      expect(Defaults.get_environment_from_plan_key("AMS01-C008S04PROD")).to eq("prod")
    end
  end

  context '.create_dns_record' do
    it 'creates dns record' do
      allow(Util::Nsupdate).to receive(:update_dns_record)
      expect(Log).to receive(:info).with(/Creating DNS record/)
      Util::Nsupdate.create_dns_record("value", "target", "type", 60)
    end
  end

  context '.delete_dns_record' do
    it 'deletes dns record' do
      allow(Util::Nsupdate).to receive(:update_dns_record)
      expect(Log).to receive(:info).with(/Deleting DNS record/)
      Util::Nsupdate.delete_dns_record("value")
    end
  end

  context '.image_by_dns' do
    it 'image_by_dns' do
      expect(Log).to receive(:debug).with("Checking DNS for AMI matching record image.master-158.dev.c031-98.ams01.#{Defaults.dns_zone}")
      Defaults.image_by_dns("image.master-158.dev.c031-98.ams01")
    end
  end

  context '.update_dns_record' do
    it 'raises error if mandatory arguments are missing' do
      expect {
        Util::Nsupdate.update_dns_record(dns_name: nil, action: 'add', target: "target", type: "type", ttl: 60)
      }.to raise_error(ArgumentError, /Expecting DNS name/)
      expect {
        Util::Nsupdate.update_dns_record(dns_name: 'something', action: nil, target: "target", type: "type", ttl: 60)
      }.to raise_error(ArgumentError, /Expecting DNS action/)
    end

    it 'actions on the dns record', :skip => true do
      allow(Util::Nsupdate).to receive(:run_command)
      allow(Defaults).to receive_message_chain('ad_zone_dns').and_return('qcpaws.qantas.com.au')
      allow(Defaults).to receive_message_chain('keytab_path').and_return('keytab')
      allow(Defaults).to receive_message_chain('ad_principle').and_return('principle')
      allow(Defaults).to receive_message_chain('ad_domain_dc_list').and_return(%w(awssyddc07 awssyddc08))
      expect(Log).to receive(:error).with ("Unable to run nsupdate on server: awssyddc07")
      expect(Log).to receive(:error).with ("Unable to run nsupdate on server: awssyddc08")
      expect {
        Util::Nsupdate.update_dns_record(dns_name: 'testing.qcpaws.qantas.com.au', action: 'add')
      }.to raise_error(RuntimeError)
    end

    it 'ssm parameter dns records', :skip => true do
      allow(Util::Nsupdate).to receive(:run_command)
      allow(Defaults).to receive_message_chain('ad_zone_dns').and_return('qcpaws.qantas.com.au')
      allow(Defaults).to receive_message_chain('keytab_path').and_return('keytab')
      allow(Defaults).to receive_message_chain('ad_principle').and_return('principle')
      allow(Defaults).to receive_message_chain('ad_domain_dc_list').and_return(%w(awssyddc09 awssyddc10))
      expect(Log).to receive(:error).with ("Unable to run nsupdate on server: awssyddc09")
      expect(Log).to receive(:error).with ("Unable to run nsupdate on server: awssyddc10")
      expect {
        Util::Nsupdate.update_dns_record(dns_name: 'testing.qcpaws.qantas.com.au', action: 'add')
      }.to raise_error(RuntimeError)
    end
  end

  context '.run_command' do
    it 'issues commands to stdin and logs stdout' do
      allow(Log).to receive(:debug)
      expect(Log).to receive(:debug).with(/test command output \(STDOUT\)/)

      # use dir for win and ls for other OS
      if windows?
        Util::Nsupdate.run_command("test", "dir", stdin = nil)
      else
        Util::Nsupdate.run_command("test", "ls", stdin = nil)
      end

      expect {
        Util::Nsupdate.run_command("test", "some_invalid_command", stdin = nil)
      }.to raise_error(Errno::ENOENT)
    end
  end

  context '.get_tags' do
    it 'returns tags' do
      allow(Defaults).to receive(:sections).and_return(@test_data["Mock"]["ContextSections"])
      expect(
        Defaults.get_tags(@test_data["UnitTest"]["get_tags"]["Input"])
      ).to eq(@test_data["UnitTest"]["get_tags"]["OutputWithComponent"])
      expect(
        Defaults.get_tags
      ).to eq(@test_data["UnitTest"]["get_tags"]["OutputWithOutComponent"])
    end
  end

  context '.get_sections' do
    it 'raises error if plankey is not in expected datetime_format' do
      expect {
        Defaults.get_sections("something")
      }.to raise_error(RuntimeError, /Unable to retrieve sections/)
    end

    it 'returns sections for valid plankey' do
      expect(
        Defaults.get_sections(
          *@test_data["UnitTest"]["get_sections"]["Input"]
        )
      ).to eq @test_data["UnitTest"]["get_sections"]["Output"]
    end
  end

  context '.kms_stack_name' do
    it 'returns kms_stack_name' do
      allow(Defaults).to receive(:sections).and_return(@test_data["Mock"]["ContextSections"])
      expect(Defaults.kms_stack_name).to eq @test_data["UnitTest"]["kms_stack_name"]["Output"]
    end
  end

  context '.image_name' do
    it 'returns component_stack_name' do
      allow(Defaults).to receive(:sections).and_return(@test_data["Mock"]["ContextSections"])
      expect(Defaults.image_name(@test_data["UnitTest"]["image_name"]["Input"]['source_image_name'], @test_data["UnitTest"]["image_name"]["Input"]['component_name']))
        .to match Regexp.new(@test_data["UnitTest"]["image_name"]["Output"])
    end
  end

  context '.component_stack_name' do
    it 'returns component_stack_name' do
      allow(Defaults).to receive(:sections).and_return(@test_data["Mock"]["ContextSections"])
      expect(
        Defaults.component_stack_name(
          @test_data["UnitTest"]["component_stack_name"]["Input"]
        )
      ).to eq @test_data["UnitTest"]["component_stack_name"]["Output"]
    end
  end

  context '.deployment_dns_name' do
    it 'returns deployment_dns_name - ad' do
      allow(Defaults).to receive(:dns_zone).and_return(Defaults.ad_dns_zone)

      allow(Defaults).to receive(:sections).and_return(@test_data["Mock"]["ContextSections"])
      expect(
        Defaults.deployment_dns_name(
          component: @test_data["UnitTest"]["deployment_dns_name"]["Component"],
          resource: @test_data["UnitTest"]["deployment_dns_name"]["Resource"]
        )
      ).to eq @test_data["UnitTest"]["deployment_dns_name_ad"]["Output"]
    end

    it 'returns deployment_dns_name - route53' do
      allow(Defaults).to receive(:dns_zone).and_return(Defaults.r53_dns_zone)
      allow(Defaults).to receive(:sections).and_return(@test_data["Mock"]["ContextSections"])
      expect(
        Defaults.deployment_dns_name(
          component: @test_data["UnitTest"]["deployment_dns_name"]["Component"],
          resource: @test_data["UnitTest"]["deployment_dns_name"]["Resource"]
        )
      ).to eq @test_data["UnitTest"]["deployment_dns_name_r53"]["Output"]
    end
  end

  context '.release_dns_name' do
    it 'returns release_dns_name - ad' do
      allow(Defaults).to receive(:dns_zone).and_return(Defaults.ad_dns_zone)
      allow(Defaults).to receive(:sections).and_return(@test_data["Mock"]["ContextSections"])
      expect(
        Defaults.release_dns_name(
          component: @test_data["UnitTest"]["release_dns_name"]["Component"],
          resource: @test_data["UnitTest"]["release_dns_name"]["Resource"]
        )
      ).to eq @test_data["UnitTest"]["release_dns_name_ad"]["Output"]
    end

    it 'returns release_dns_name - route53' do
      allow(Defaults).to receive(:dns_zone).and_return(Defaults.r53_dns_zone)
      allow(Defaults).to receive(:sections).and_return(@test_data["Mock"]["ContextSections"])
      expect(
        Defaults.release_dns_name(
          component: @test_data["UnitTest"]["release_dns_name"]["Component"],
          resource: @test_data["UnitTest"]["release_dns_name"]["Resource"]
        )
      ).to eq @test_data["UnitTest"]["release_dns_name_r53"]["Output"]
    end
  end

  context '.component_security_stack_name' do
    it 'returns component_security_stack_name' do
      allow(Defaults).to receive(:sections).and_return(@test_data["Mock"]["ContextSections"])
      expect(
        Defaults.component_security_stack_name(
          @test_data["UnitTest"]["component_security_stack_name"]["Input"]
        )
      ).to eq @test_data["UnitTest"]["component_security_stack_name"]["Output"]
    end
  end

  context '.security_rules_stack_name' do
    it 'returns security_rules_stack_name' do
      allow(Defaults).to receive(:sections).and_return(@test_data["Mock"]["ContextSections"])
      expect(
        Defaults.security_rules_stack_name(@test_data["UnitTest"]["security_rules_stack_name"]["Input"])
      ).to eq @test_data["UnitTest"]["security_rules_stack_name"]["Output"]
    end
  end

  context '.asir_source_group_stack_name' do
    it 'returns asir_source_group_stack_name' do
      allow(Defaults).to receive(:sections).and_return(@test_data["Mock"]["ContextSections"])
      expect(
        Defaults.asir_source_group_stack_name(
          @test_data["UnitTest"]["asir_source_group_stack_name"]["Input"]
        )
      ).to eq @test_data["UnitTest"]["asir_source_group_stack_name"]["Output"]
    end
  end

  context '.asir_destination_group_stack_name' do
    it 'returns asir_destination_group_stack_name' do
      allow(Defaults).to receive(:sections).and_return(@test_data["Mock"]["ContextSections"])
      expect(Defaults.asir_destination_group_stack_name())
        .to eq @test_data["UnitTest"]["asir_destination_group_stack_name"]["Output"]
    end
  end

  context '.asir_destination_rules_stack_name' do
    it 'returns asir_destination_rules_stack_name' do
      allow(Defaults).to receive(:sections).and_return(@test_data["Mock"]["ContextSections"])
      expect(
        Defaults.asir_destination_rules_stack_name()
      ).to eq @test_data["UnitTest"]["asir_destination_rules_stack_name"]["Output"]
    end
  end

  context 'r53_hosted_zone' do
    it 'returns route 53 dns zone based on the environment' do
      allow(Defaults).to receive(:dns_zone).and_return(Defaults.r53_hosted_zone)
      allow(Defaults).to receive(:sections).and_return(@test_data["Mock"]["ContextSections"])
      expect(Defaults.r53_hosted_zone).to eq "ams01.nonp.aws.qcp"
    end

    it 'returns route 53 dns zone based public dns zone' do
      allow(Defaults).to receive(:dns_zone).and_return("public_zone")
      allow(Defaults).to receive(:sections).and_return(@test_data["Mock"]["ContextSections"])
      expect(Defaults.r53_hosted_zone).to eq "public_zone"
    end
  end
end # RSpec.describe
