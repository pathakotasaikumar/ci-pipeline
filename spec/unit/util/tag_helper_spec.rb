$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib/util"))
require 'tag_helper.rb'
require 'os'

RSpec.describe TagHelper do
  context 'get_tag_values' do
    it 'successfully return soe tag if SOE_ID not present in soe tags' do
      input_tags = [{ key: "AMSID", value: "AMS01" }, { key: "EnterpriseAppID", value: "C031" }, { key: "ApplicationServiceID", value: "01" }]
      soe_name = "qf-aws-win2016-x86_64-1000.1"
      input_tag = "SOE_ID"
      expect(TagHelper.get_tag_values(tags: input_tags, default_value: soe_name, tag_key: input_tag)).to eq([{ key: "SOE_ID", value: "qf-aws-win2016-x86_64-1000.1" }])
    end

    it 'successfully return soe tag if SOE_ID present in soe tags' do
      input_tags = [{ key: "AMSID", value: "AMS01" }, { key: "EnterpriseAppID", value: "C031" }, { key: "ApplicationServiceID", value: "01" }, { key: "SOE_ID", value: "qf-aws-win2016-x86_64-1000.3" }]
      soe_name = "qf-aws-win2016-x86_64-1000.1"
      input_tag = "SOE_ID"
      expect(TagHelper.get_tag_values(tags: input_tags, default_value: soe_name, tag_key: input_tag)).to eq([{ key: "SOE_ID", value: "qf-aws-win2016-x86_64-1000.3" }])
    end

    it 'successfully return soe tags are empty ' do
      input_tags = []
      soe_name = "qf-aws-win2016-x86_64-1000.1"
      input_tag = "SOE_ID"
      expect(TagHelper.get_tag_values(tags: input_tags, default_value: soe_name, tag_key: input_tag)).to eq([{ key: "SOE_ID", value: "qf-aws-win2016-x86_64-1000.1" }])
    end
  end
end
