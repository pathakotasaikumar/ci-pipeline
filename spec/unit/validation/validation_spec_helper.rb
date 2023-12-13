require 'consumable'
require 'validation/validation_service'

shared_context 'shared_validation_context' do
  def standard_pass_tests(service:, spec_file:)
    data = ValidationSpecHelper.get_pass_data(spec_file)
    result = service.validate(data: data)

    ValidationSpecHelper.print_validation_result(result)

    expect(result).not_to be(nil)
    expect(result.count > 0).to eq(true)

    result.each do |validation_result|
      expect(validation_result.valid).to eq(true)
    end
  end

  def standard_fail_tests(service:, spec_file:)
    data = ValidationSpecHelper.get_fail_data(spec_file)
    result = service.validate(data: data)

    ValidationSpecHelper.print_validation_result(result)

    expect(result).not_to be(nil)
    expect(result.count > 0).to eq(true)

    result.each do |validation_result|
      expect(validation_result.valid).to eq(false)
    end
  end
end

module ValidationSpecHelper
  extend self

  def pass_component_files(spec_file)
    load_component_files(spec_file, "pass")
  end

  def fail_component_files(spec_file)
    load_component_files(spec_file, "fail")
  end

  def load_component_files(spec_file, type)
    if spec_file.nil?
      raise "spec_file is required"
    end

    path = "#{TEST_DATA_DIR}/validation/#{File.basename(spec_file, ".*")}/#{type}/*.yaml"
    component_files = Dir[path]

    if component_files.empty?
      raise "Cannot find any file of type '#{type}' for path: #{path}"
    end

    component_files
  end

  def get_pass_components(spec_file)
    get_components(pass_component_files(spec_file))
  end

  def get_fail_components(spec_file)
    get_components(fail_component_files(spec_file))
  end

  def print_validation_result(result)
    result.each do |validation_result|
      Log.warn validation_result
    end
  end

  def get_pass_data(spec_file)
    app_container_info = AppContainerInfo.new(sections: Defaults.sections)

    data = ValidationData.new
    data.app_containers[app_container_info] = get_pass_components(spec_file)

    data
  end

  def get_fail_data(spec_file)
    app_container_info = AppContainerInfo.new(sections: Defaults.sections)

    data = ValidationData.new
    data.app_containers[app_container_info] = get_fail_components(spec_file)

    data
  end

  def get_components(file_paths)
    result = []

    file_paths.each do |file_path|
      extn = File.extname file_path
      name = File.basename file_path, extn

      component_info = ValidationComponentInfo.new

      component_info.component_file = file_path
      component_info.component_name = name
      component_info.component_hash = YAML.load(File.read(file_path))

      result << component_info
    end

    result
  end
end
