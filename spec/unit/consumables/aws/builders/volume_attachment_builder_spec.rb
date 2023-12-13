$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws/builders")
require 'volume_attachment_builder'
require 'security_item_builder'
require 'security_rule_builder'
RSpec.describe VolumeAttachmentBuilder do
  include SecurityItemBuilder
  include SecurityRuleBuilder

  before(:context) do
    @dummy_class = DummyClass.new
    @dummy_class.extend(VolumeAttachmentBuilder)
    @input = YAML.load(
      File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"),
      permitted_classes: ['IamSecurityRule']
    )['Input']
    @output = YAML.load(
      File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"),
      permitted_classes: ['IamSecurityRule']
    )['Output']
    Context.component.set_variables("volume1", { "MyVolumeId" => "vol-123456780" })
    Context.component.set_variables("volume2", { "MyVolumeId" => "vol-098765432" })
  end

  context '._volume_attachment_security_rules' do
    it 'valid parse 1' do
      allow(Context).to receive_message_chain('environment.region').and_return('ap-southeast-2')
      allow(Context).to receive_message_chain('environment.account_id').and_return('dummy-account')
      allow(Context).to receive_message_chain('kms.secrets_key_arn').and_return('kms-dummy')

      security_rules = @dummy_class._volume_attachment_security_rules(
        volume_attachments: @input['Valid1'],
        component_name: 'autoheal',
        execution_role_name: 'TestRol1',
      )
      expect(security_rules).to eq(@output['_volume_attachment_security_rules']['Valid1'])
    end
  end

  context '._parse_volume_attachments' do
    it 'valid parse 1' do
      expect(@dummy_class._parse_volume_attachments(@input['Valid1']))
        .to eq(@output['_parse_volume_attachments']['Valid1'])
    end

    it 'valid parse 2' do
      expect(@dummy_class._parse_volume_attachments(@input['Valid2']))
        .to eq(@output['_parse_volume_attachments']['Valid2'])
    end

    it 'invalid parse 1' do
      expect { @dummy_class._parse_volume_attachments(@input['Invalid1']) }
        .to raise_error(ArgumentError, /Invalid value specified for device/)
    end

    it 'invalid parse 2' do
      expect { @dummy_class._parse_volume_attachments(@input['Invalid2']) }
        .to raise_error(ArgumentError, /Invalid value specified for device/)
    end
  end
end # RSpec.describe
