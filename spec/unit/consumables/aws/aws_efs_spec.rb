$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib/consumables/aws"))
require 'aws_efs'

RSpec.describe AwsEfs do
  include_examples "shared context"

  before(:context) do
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))
    subnets = {
      "dev-qantas-ap-southeast-2a-private" => {
        :id => "subnet-20008945",
        :availability_zone => "ap-southeast-2a"
      }
    }
    Context.environment.set_variables({ 'aws_subnet_ids' => subnets })
    Context.component.set_security_details("efs", "securitystack-123", { 'SecurityGroupId' => 'sg-app-security', 'ElbSecurityGroupId' => 'sg-app-elb', 'InstanceRoleArn' => 'ams99-c001-01-dev-master-1-app-InstanceRole-1BYMM7M4RPVEE' })
  end

  context '._build_template' do
    it 'generates default / customised templates - ad' do
      valid_component_name = "efs"
      allow(Defaults).to receive(:dns_zone).and_return(Defaults.ad_dns_zone)
      allow(Context).to receive_message_chain('kms.secrets_key_arn').and_return('arn:aws:kms:ap-southeast-2:111122223333:key/1234abcd-12ab-34cd-56ef-1234567890ab')
      efs = AwsEfs.new(valid_component_name, @test_data[context_description]["Input"])
      expect(efs.send :_build_template).to eq @test_data[context_description]["Output"]
    end

    it 'generates default / customised templates - route53' do
      valid_component_name = "efs"
      allow(Defaults).to receive(:dns_zone).and_return(Defaults.r53_dns_zone)
      allow(Context).to receive_message_chain('kms.secrets_key_arn').and_return('arn:aws:kms:ap-southeast-2:111122223333:key/1234abcd-12ab-34cd-56ef-1234567890ab')
      efs = AwsEfs.new(valid_component_name, @test_data[context_description]["Input"])
      expect(efs.send :_build_template).to eq @test_data[context_description]["Output-Route53"]
    end
  end

  context '.initalize', :skip => true do
    it 'does something' do
      pending
      AwsSqs.initalize(component_name, component)
      expect { 1 }.eq 1
    end
  end

  context '.get_access_rules', :skip => true do
    it 'does something' do
      pending
      AwsSqs.get_access_rules()
      expect { 1 }.eq 1
    end
  end

  context '.deploy', :skip => true do
    it 'does something' do
      pending
      AwsSqs.deploy
      expect { 1 }.eq 1
    end
  end

  context '.release', :skip => true do
    it 'does something' do
      pending
      AwsSqs.release
      expect { 1 }.eq 1
    end
  end

  context '.teardown', :skip => true do
    it 'does something' do
      pending
      AwsSqs.teardown
      expect { 1 }.eq 1
    end
  end
end # RSpec.describe
