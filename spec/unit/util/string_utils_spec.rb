$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib/util"))
require 'string_utils.rb'

RSpec.describe StringUtils do
  context 'compare_upcase' do
    it 'test successful true' do
      result = StringUtils.compare_upcase('test', 'TeSt')
      expect(result).to eq(true)
    end

    it 'test successful false' do
      result = StringUtils.compare_upcase('test', 'TeS')
      expect(result).to eq(false)
    end

    it 'nothing passed - 1, typos, forgot to pass anything' do
      expect {
        StringUtils.compare_upcase()
      }.to raise_exception(ArgumentError, /wrong number of arguments/)
    end

    it 'nothing passed - 2, typos, forgot to pass anything' do
      expect {
        StringUtils.compare_upcase("test-1")
      }.to raise_exception(ArgumentError, /wrong number of arguments/)
    end

    it 'nil passed - 1, second incoming value was nil ' do
      expect {
        StringUtils.compare_upcase("test-1", nil)
      }.to raise_exception(RuntimeError, /contains one or more nil values/)
    end

    it 'nil passed - 2, first incoming value was nil' do
      expect {
        StringUtils.compare_upcase(nil, "test-2")
      }.to raise_exception(RuntimeError, /contains one or more nil values/)
    end
  end

  context '.generate_string' do
    it 'generates string' do
      value = StringUtils.generate_string

      expect(value).not_to be(nil)
      expect(value.length).to eq(32)
    end

    it 'generates giving string' do
      value = StringUtils.generate_string(length: 16)

      expect(value).not_to be(nil)
      expect(value.length).to eq(16)
    end

    it 'generates random string correct length' do
      value = StringUtils.generate_string(length: 11, charset: 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*()[]/\|=?+{}-')

      expect(value.length).to eq(11)
    end
  end
end
