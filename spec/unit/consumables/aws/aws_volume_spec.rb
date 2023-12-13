$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws")
require 'aws_volume'

RSpec.describe AwsVolume do
  before(:context) do
    @test_data = YAML.load(
      File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"),
      permitted_classes: ['IamSecurityRule']
    )['UnitTest']
    @component_name = @test_data['Input']['ComponentName']
  end

  context '.initialize' do
    it 'initialises without error' do
      expect {
        AwsVolume.new(@component_name, @test_data['Input']['Initialize']['Valid'])
      }.not_to raise_exception

      expect {
        AwsVolume.new(@component_name, @test_data['Input']['Initialize']['Invalid'])
      }.to raise_exception(RuntimeError)
    end
  end

  context '.security_items' do
    it 'retuns []' do
      aws_volume = AwsVolume.new(@component_name, @test_data['Input']['Initialize']['Valid'])
      expect(aws_volume.security_items).to eq []
    end
  end

  context '.security_rules' do
    it 'retuns security rules' do
      aws_volume = AwsVolume.new(@component_name, @test_data['Input']['Initialize']['Valid'])
      expect(aws_volume.security_rules).to eq @test_data['Output']['security_rules']
    end
  end

  context '.deploy' do
    it 'deploys stack and creates dns' do
      aws_volume = AwsVolume.new(@component_name, @test_data['Input']['Initialize']['Valid'])
      allow(aws_volume).to receive(:_build_template)
      allow(AwsHelper).to receive(:cfn_create_stack)
      allow(Context).to receive_message_chain('component.set_variables')
      allow(Defaults).to receive(:ad_dns_zone?).and_return(nil)

      expect { aws_volume.deploy }.not_to raise_exception
    end

    it 'deploys stack and fail dns creation' do
      aws_volume = AwsVolume.new(@component_name, @test_data['Input']['Initialize']['Valid'])
      allow(aws_volume).to receive(:_build_template)
      allow(AwsHelper).to receive(:cfn_create_stack)
      allow(Context).to receive_message_chain('component.set_variables')
      allow(Context).to receive_message_chain('component.variable')
      allow(Defaults).to receive(:ad_dns_zone?).and_return(true)
      allow(aws_volume).to receive(:deploy_ad_dns_records).and_raise(RuntimeError)
      expect { aws_volume.deploy }.to raise_exception /Failed to deploy DNS records/
    end
  end

  context '.release' do
    it 'switches dns' do
      load_mocks @test_data['Input']['Mock2']
      aws_volume = AwsVolume.new(@component_name, @test_data['Input']['Initialize']['Valid'])
      expect { aws_volume.release }.not_to raise_exception
    end
  end

  context '.teardown' do
    it 'deletes dns' do
      load_mocks @test_data['Input']['Mock1']
      aws_volume = AwsVolume.new(@component_name, @test_data['Input']['Initialize']['Valid'])
      expect { aws_volume.teardown }.not_to raise_exception
    end
  end

  context '_load_volume_snaps_tags' do
    it 'return default tags' do
      aws_volume = AwsVolume.new(@component_name, @test_data['Input']['Initialize']['ValidSourceSnapshot'])
      allow(PipelineMetadataService).to receive(:load_metadata).and_return('1')
      expect { aws_volume.send :_load_volume_snaps_tags }.not_to raise_exception
      expect(aws_volume.send :_load_volume_snaps_tags).to eq({ :ase => "STG", :branch => "master", :component => "TestComponent", :resource => "Volume", :build => "1" })
    end
    it 'test prod env tags' do
      aws_volume = AwsVolume.new(@component_name, @test_data['Input']['Initialize']['ValidPRODSourceSnapshot'])
      allow(PipelineMetadataService).to receive(:load_metadata).and_return('2')
      expect { aws_volume.send :_load_volume_snaps_tags }.not_to raise_exception
      expect(aws_volume.send :_load_volume_snaps_tags).to eq({ :ase => "PROD", :branch => "master", :component => "TestComponent", :resource => "Volume", :build => "2" })
    end
  end
end # RSpec.describe
