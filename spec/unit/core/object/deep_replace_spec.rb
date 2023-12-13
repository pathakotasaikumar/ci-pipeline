$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib/core/object"))
require 'deep_replace.rb'

RSpec.describe Object do
  Object.include Core::Object::DeepReplace

  context 'process_nester_strings' do
    it 'return simple string replacement' do
      @input = "something"
      expect(@input.deep_replace(&:upcase)).to eq('SOMETHING')
    end

    it 'returns empty string replacement' do
      @input = ""
      expect(@input.deep_replace(&:upcase)).to eq('')
    end

    it 'return nil replacement' do
      @input = nil
      expect(@input.deep_replace(&:upcase)).to eq(nil)
    end

    it 'returns simple hash replacement' do
      @input = { a: 'b', b: 'd' }
      @output = { a: 'B', b: 'D' }

      expect(@input.deep_replace(&:upcase)).to eq(@output)
    end

    it 'return simple hash replacement with FixNums' do
      @input = { a: 1, b: 2 }
      @output = { a: 1, b: 2 }
      expect(@input.deep_replace(&:upcase)).to eq(@output)
    end

    it 'returns array nested in hash replacement' do
      @input = { a: 1, b: ['a', :b, nil, 'c'] }
      @output = { a: 1, b: ['A', :b, nil, 'C'] }
      expect(@input.deep_replace(&:upcase)).to eq(@output)
    end

    it 'returns nested hash replacement' do
      @input = { a: 1, b: { a: 'a', b: nil, c: 'c' } }
      @output = { a: 1, b: { a: 'A', b: nil, c: 'C' } }
      expect(@input.deep_replace(&:upcase)).to eq(@output)
    end

    it 'returns nested array replacement' do
      @input = [['a', 'b'], ['c', 'd']]
      @output = [['A', 'B'], ['C', 'D']]
      expect(@input.deep_replace(&:upcase)).to eq(@output)
    end

    it 'returns nested empty structure' do
      @input = { a: {}, b: [c: {}, d: []] }
      @output = { a: {}, b: [c: {}, d: []] }
      expect(@input.deep_replace(&:upcase)).to eq(@output)
    end
  end
end # RSpec.describe
