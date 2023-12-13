$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws/builders")
require 'network_attachment_builder'
require 'security_item_builder'
require 'security_rule_builder'
RSpec.describe NetworkAttachmentBuilder do
  include SecurityItemBuilder
  include SecurityRuleBuilder

  before(:context) do
    @dummy_class = DummyClass.new
    @dummy_class.extend(NetworkAttachmentBuilder)
    @input = YAML.load(
      File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"),
      permitted_classes: ['IamSecurityRule']
    )['Input']
    @output = YAML.load(
      File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"),
      permitted_classes: ['IamSecurityRule']
    )['Output']
    Context.component.set_variables("eni1", { "MyNetworkId" => "eni-123456780" })
    Context.component.set_variables("eni2", { "MyNetworkId" => "eni-098765432" })
  end

  context '._network_attachment_security_rules' do
    it 'valid parse 1' do
      security_rules = @dummy_class._network_attachment_security_rules(
        component_name: 'autoheal',
        execution_role_name: 'TestRol1'
      )

      expect(security_rules).to eq(@output['_network_attachment_security_rules']['Valid1'])
    end
  end

  context '._parse_network_attachments' do
    it 'valid parse 1' do
      expect(@dummy_class._parse_network_attachments(@input['Valid1']))
        .to eq(@output['_parse_network_attachments']['Valid1'])
    end

    it 'valid parse 2' do
      expect(@dummy_class._parse_network_attachments(@input['Valid2']))
        .to eq(@output['_parse_network_attachments']['Valid2'])
    end

    it 'invalid parse 1' do
      expect { @dummy_class._parse_network_attachments(@input['Invalid1']) }
        .to raise_error(ArgumentError, /Invalid value specified for device/)
    end

    it 'invalid parse 2' do
      expect { @dummy_class._parse_network_attachments(@input['Invalid2']) }
        .to raise_error(ArgumentError, /Invalid value specified for device/)
    end
  end
end # RSpec.describe
