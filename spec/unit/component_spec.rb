$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib"))
require 'component.rb'

RSpec.describe Component do
  before(:context) do
    @source_folder_path = "#{BASE_DIR}/platform"
    @yaml_files = Dir["#{@source_folder_path}/*.yaml"]
  end

  context '.load' do
    it 'loads component' do
      @yaml_files.each do |file_path|
        component = Component.load(file_path, "TEST", "QCP-3442")
        expect(component).not_to be(nil)
      end

      expect(@yaml_files.count > 0).to be(true)
    end

    it 'loads component with override' do
      @yaml_files.each do |file_path|
        component = Component.load(file_path, "DEV", "QCP-3442")
        expect(component).not_to be(nil)
      end

      expect(@yaml_files.count > 0).to be(true)
    end

    it 'raises error in failed component' do
      allow(YAML).to receive(:load) .and_raise('err loading YAML file')

      expect {
        component = Component.load(@yaml_files.first, "DEV", "QCP-3442")
      }.to raise_error(/Failed to read component file/)
    end
  end

  context '.load_all' do
    it 'loads all components' do
      components = Component.load_all(@source_folder_path, "TEST", "QCP-3442")
      expect(components.count > 0).to be(true)
    end
  end
end # RSpec.describe
