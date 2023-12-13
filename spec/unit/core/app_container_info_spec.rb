$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib"))
require 'core/app_container_info'

include Qantas::Pipeline::Core

RSpec.describe AppContainerInfo do
  def _get_instance
    AppContainerInfo.new(sections: {})
  end

  def _get_instance_from_sections
    AppContainerInfo.new(sections: Defaults.sections)
  end

  def _get_instance_from_hash(sections:)
    AppContainerInfo.new(sections: sections)
  end

  context '.instantiate' do
    it 'raise on wrong params' do
      expect {
        app_info = _get_instance
      }.to raise_error(KeyError, /key not found/)
    end

    it 'create from sections' do
      sections = Defaults.sections

      app_info = _get_instance_from_sections

      expect(app_info.ams).to eq(sections[:ams])
      expect(app_info.qda).to eq(sections[:qda])

      expect(app_info.as).to eq(sections[:as])
      expect(app_info.ase).to eq(sections[:ase])

      expect(app_info.ase_number).to eq(sections[:ase_number])
      expect(app_info.plan_key).to eq(sections[:plan_key])

      expect(app_info.branch).to eq(sections[:branch])
      expect(app_info.build).to eq(sections[:build])

      expect(app_info.env).to eq(sections[:env])
      expect(app_info.asbp_type).to eq(sections[:asbp_type])
    end
  end

  context '.to_s' do
    it 'can executue' do
      app_info = _get_instance_from_sections

      result = app_info.to_s

      expect(result).not_to eq(nil)
    end
  end

  context '.==' do
    it 'positive' do
      app_info1 = _get_instance_from_sections
      app_info2 = _get_instance_from_sections

      expect(app_info1 == app_info2).to eq(true)
    end

    it 'negative' do
      section_copy = Marshal.load(Marshal.dump(Defaults.sections))
      section_copy[:ams] = "42"

      app_info1 = _get_instance_from_sections
      app_info2 = _get_instance_from_hash(sections: section_copy)

      expect(app_info1 != app_info2).to eq(true)
    end
  end
end
