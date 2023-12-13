$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib/util"))

require 'yaml_include.rb'
require 'nokogiri'

RSpec.describe Util::YAMLInclude do
  before(:context) do
    Util::YAMLInclude.yaml("#{TEST_DATA_DIR}/util/yaml_include_spec/input")
    Util::YAMLInclude.yaml("#{TEST_DATA_DIR}/util/yaml_include_spec/invalid")
    Util::YAMLInclude.json("#{TEST_DATA_DIR}/util/yaml_include_spec/input")
    Util::YAMLInclude.text("#{TEST_DATA_DIR}/util/yaml_include_spec/input")
    Util::YAMLInclude.xml("#{TEST_DATA_DIR}/util/yaml_include_spec/input")
  end

  context 'yaml' do
    it 'expect exception on incorrect parsing' do
      expect {
        YAML.load_file("#{TEST_DATA_DIR}/util/yaml_include_spec/invalid/test1-invalid.yaml")
      }.to raise_error(RuntimeError, /Unable to parse/)
    end

    it 'expect yaml, json and text loaded' do
      @test_input = YAML.load_file "#{TEST_DATA_DIR}/util/yaml_include_spec/input/test1.yaml"
      @test_output = YAML.load_file "#{TEST_DATA_DIR}/util/yaml_include_spec/output/test1.yaml"
      expect(@test_input).to eq(@test_output)
    end

    it 'expect failure to find' do
      expect(Log).to receive(:warn).with(/Unable to locate/)
      expect(Log).to receive(:warn).with(/Unable to locate/)
      expect(Log).to receive(:warn).with(/Unable to locate/)

      YAML.load_file "#{TEST_DATA_DIR}/util/yaml_include_spec/input/test2.yaml"
    end

    it 'expect failure to parse' do
      # json/yaml parsing
      expect {
        YAML.load_file "#{TEST_DATA_DIR}/util/yaml_include_spec/input/test3.yaml"
      }.to raise_error /Unable to parse/

      allow(File).to receive(:read).and_raise("Unable to parse text file")
      # txt reading error
      expect {
        YAML.load_file "#{TEST_DATA_DIR}/util/yaml_include_spec/input/test4.yaml"
      }.to raise_error /Unable to parse text file/
    end

    it 'except failure to find xml file' do
      expect {
        YAML.load_file "#{TEST_DATA_DIR}/util/yaml_include_spec/input/test_invalid_xml_config.yaml"
      }.to raise_error(RuntimeError)
    end

    it 'expect should throw unknown file error' do
      expect(Log).to receive(:warn).with(/Unable to locate/)
      YAML.load_file "#{TEST_DATA_DIR}/util/yaml_include_spec/input/test6.yaml"
    end
  end
end
