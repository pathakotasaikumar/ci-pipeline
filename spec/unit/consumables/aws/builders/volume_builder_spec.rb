$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws/builders")
require 'volume_builder'

RSpec.describe VolumeBuilder do
  before(:context) do
    @dummy_class = DummyClass.new
    @dummy_class.extend(VolumeBuilder)
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))['UnitTest']
  end
  context '._process_volume' do
    it 'return volume template for VolumeMinimal' do
      template = @test_data['Input']['Template']
      load_mocks @test_data['Input']['Mock']
      allow(Context)
        .to receive_message_chain('kms.secrets_key_arn')
        .and_return('kms-dummy')
      @dummy_class._process_volume(template: template, snapshot_id: nil, volume_definition: @test_data["Input"]["Definitions"]["Valid"]["VolumeMinimal"])
      expect(template).to eq @test_data["Output"]["VolumeMinimal"]
    end

    it 'return volume template for VolumeSnapshot' do
      template = @test_data['Input']['Template']
      load_mocks @test_data['Input']['Mock']
      allow(Context)
        .to receive_message_chain('kms.secrets_key_arn')
        .and_return('kms-dummy')
      @dummy_class._process_volume(template: template, snapshot_id: nil, volume_definition: @test_data["Input"]["Definitions"]["Valid"]["VolumeSnapshot"])
      expect(template).to eq @test_data["Output"]["VolumeSnapshot"]
    end

    it 'return volume template for VolumeRestore' do
      template = @test_data['Input']['Template']
      load_mocks @test_data['Input']['Mock']
      allow(Context)
        .to receive_message_chain('kms.secrets_key_arn')
        .and_return('kms-dummy')
      @dummy_class._process_volume(template: template, snapshot_id: "sn123", volume_definition: @test_data["Input"]["Definitions"]["Valid"]["VolumeRestore"])
      expect(template).to eq @test_data["Output"]["VolumeRestore"]
    end

    it 'raises error for invalid landscape specification' do
      @test_data['Input']['Definitions']['Invalid'].each_with_index { |volume_definiton, index|
        template = @test_data['Input']['Template']
        load_mocks @test_data['Input']['Mock']
        expect {
          @dummy_class._process_volume(template: template, volume_definition: volume_definiton)
        }.to raise_error(RuntimeError)
      }
    end

    it 'raises error for not found app KMS key' do
      allow(Context).to receive_message_chain('environment.availability_zones')
        .and_return(['zone1', 'zone2'])

      allow(Context).to receive_message_chain('kms.secrets_key_arn')
        .and_return(nil)

      expect {
        @dummy_class._process_volume(
          template: {
            'Resources' => {}
          },
          volume_definition: {
            'my-component' => {
              'Properties' => {
                'AvailabilityZone' => 'zone1',
                'VolumeType' => 'tmp',
                'Size' => 100
              }
            }
          },
          snapshot_id: nil
        )
      }.to raise_error(/KMS key for application service/)
    end
  end
end # RSpec.describe
