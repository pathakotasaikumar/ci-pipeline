$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib/util"))
require 'json_tools.rb'
require 'os'

RSpec.describe JsonTools do
  before(:context) do
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))
  end

  include_examples "shared context"

  context '.contain_value' do
    it 'returns true on nil' do
      expect(JsonTools.contain_value?(nil, 1)).to eq(true)
    end

    it 'works with hash, array and simple types' do
      data = {
        'name' => 'John',
        'age' => 14,
        'ids' => [1, 2, 3]
      }

      expect(JsonTools.contain_value?(data, 'John')).to eq(true)
      expect(JsonTools.contain_value?(data, 14)).to eq(true)
      expect(JsonTools.contain_value?(data, 3)).to eq(true)

      expect(JsonTools.contain_value?(data, 'Name')).to eq(false)
      expect(JsonTools.contain_value?(data, '1')).to eq(false)
      expect(JsonTools.contain_value?(data, 5)).to eq(false)
    end
  end

  context '.get_from_hash' do
    it 'find value' do
      data = {
        'name' => 'John',
        'age' => 14,
        'ids' => [1, 2, 3]
      }

      expect(JsonTools.get_from_hash(data, 'name')).to eq('John')
      expect(JsonTools.get_from_hash(data, 'age')).to eq(14)
      expect(JsonTools.get_from_hash(data, 'ids')).to eq([1, 2, 3])
    end

    it 'returns default value' do
      data = {
        'name' => 'John',
        'age' => 14,
        'ids' => [1, 2, 3]
      }

      expect(JsonTools.get_from_hash(data, 'second_name', 'Smith')).to eq('Smith')
      expect(JsonTools.get_from_hash(data, 'second_age', 314)).to eq(314)
      expect(JsonTools.get_from_hash(data, 'second_ids', [1])).to eq([1])
    end

    it 'raises exception without default value' do
      data = {
        'name' => 'John',
        'age' => 14,
        'ids' => [1, 2, 3]
      }

      expect {
        JsonTools.get_from_hash(data, 'second_name')
      }.to raise_exception(/Cannot find/)
    end
  end

  context '.set_in_hash' do
    it 'merges hash' do
      data = {
        'name' => 'John',
        'age' => 14,
        'ids' => [1, 2, 3]
      }

      additional_hash = {
        'orders' => 1,
        'salary' => 2000,
        'is_active' => false
      }

      result = JsonTools.set_in_hash(data, additional_hash)

      # result included both keys from data & additional_hash hashes
      expect(
        (result.keys & data.keys) == data.keys && (result.keys & additional_hash.keys) == additional_hash.keys
      ).to eq(true)

      # result included both values from data & additional_hash hashes
      expect(
        (result.values & data.values) == data.values && (result.values & additional_hash.values) == additional_hash.values
      ).to eq(true)

      # per value check
      result.keys.each do |key|
        value = result[key]

        expect(
          (data.keys.include?(key) && data[key] == value) || (additional_hash.keys.include?(key) && additional_hash[key] == value)
        ).to eq(true)
      end
    end

    it 'merges hash with prefix' do
      data = {
        'name' => 'John',
        'age' => 14,
        'ids' => [1, 2, 3]
      }

      expect {
        JsonTools.get_from_hash(data, 'second_name')
      }.to raise_exception(/Cannot find/)
    end
  end

  context '.hash_to_cfn_join' do
    it 'raises exception on non-hash' do
      expect { JsonTools.hash_to_cfn_join("") }.to raise_exception(ArgumentError)
      expect { JsonTools.hash_to_cfn_join(1) }.to raise_exception(ArgumentError)
      expect { JsonTools.hash_to_cfn_join(nil) }.to raise_exception(ArgumentError)

      expect { JsonTools.hash_to_cfn_join({}) }.not_to raise_exception
    end

    it 'works on hash key/values' do
      data = {
        { 'name' => 'John' } => 1,
        { 'name' => 'Smith' } => 2
      }

      expect { JsonTools.hash_to_cfn_join(data) }.not_to raise_exception
    end

    it 'works on hash value' do
      data = {
        "1" => { 'name' => 'John' },
        "2" => { 'name' => 'Smith' }
      }

      expect { JsonTools.hash_to_cfn_join(data) }.not_to raise_exception
    end
  end

  context '.delete_from_hash' do
    it 'deletes key from hash' do
      data = {
        'name' => 'John',
        'age' => 14,
        'ids' => [1, 2, 3]
      }

      JsonTools.delete_from_hash(data, ['name', 'age'])
      expect(data.keys).to eq(['ids'])
    end
  end

  context '.first' do
    it 'returns first value' do
      data = [
        'first',
        'second',
        'thord'
      ]

      result = JsonTools.first('first', data)
      expect(result).to eq('first')
    end

    it 'skips nil value' do
      data = [
        nil,
        'second',
        'thord'
      ]

      result = JsonTools.first('first', data)
      expect(result).to eq('second')
    end

    it 'returns default value' do
      data = [
        nil,
        nil,
        nil
      ]

      result = JsonTools.first('first', data, 42)
      expect(result).to eq(42)
    end

    it 'raises exception on empty default value' do
      data = [
        nil,
        nil,
        nil
      ]

      expect {
        JsonTools.first('first', data)
      }.to raise_error(/Could not determine/)
    end
  end

  context '.set_unless_nil' do
    it 'set non-nil value' do
      data = {
        'name' => 'John',
        'age' => 14,
        'ids' => [1, 2, 3]
      }

      JsonTools.set_unless_nil(data, 'name', nil)
      expect(data['name']).to eq('John')

      JsonTools.set_unless_nil(data, 'name', 'Smith')
      expect(data['name']).to eq('Smith')

      JsonTools.set_unless_nil(data, 'age', nil)
      expect(data['age']).to eq(14)

      JsonTools.set_unless_nil(data, 'age', 28)
      expect(data['age']).to eq(28)
    end
  end

  context '.parse' do
    it 'parses text to json as expected' do
      expect(JsonTools.parse(@test_data["ValidJSON"])).to eq(@test_data["ValidResult"])
    end

    it 'throws expection when invalid json is provided' do
      expect { JsonTools.parse(@test_data["InvalidJSON"]) }.to raise_error(JSON::ParserError)
    end
  end

  context '.pretty_generate' do
    it 'formats json with correct indents and carriage returns' do
      expect(JsonTools.pretty_generate(@test_data["ValidResult"])).to eq(@test_data["ValidResultPretty"])
    end
  end

  context '.get_value' do
    it 'returns json content based on keys' do
      expect(JsonTools.get(@test_data["ValidResult"], "glossary.title", default = :undef)).to eq(@test_data["ValidResult"]["glossary"]["title"])
    end

    it 'retuns exception if key not found' do
      expect { JsonTools.get(@test_data["ValidResult"], "glossary.title?", default = :undef) }.to raise_error(RuntimeError)
    end
  end
  context '.set' do
    it 'valid the return hash value' do
      test_data = @test_data["ValidResult"]["glossary"]["title"]
      expect(JsonTools.set(test_data, "glossary.title")).to eq({ "glossary" => { "title" => "example glossary" } })
    end
  end

  context '.recursive_merge' do
    it 'Fail if the input is not hash' do
      expect { JsonTools.recursive_merge("test_data", "glossary.title") }.to raise_exception /Parameters must be an Hash/
    end

    it 'Fail if the merge_From is not hash' do
      input2 = { key3: "value3", key2: ["2"] }
      expect { JsonTools.recursive_merge("test_data", input2) }.to raise_exception /Parameters must be an Hash/
    end

    it 'Fail if the merge_to is not hash' do
      input1 = { key3: "value3", key2: ["2"] }
      expect { JsonTools.recursive_merge(input1, "test_data") }.to raise_exception /Parameters must be an Hash/
    end

    it 'Success merge return' do
      input1 = { key1: "value1", key2: ["1"] }
      input2 = { key3: "value3", key2: ["2"] }
      expected = { key1: "value1", key2: ["1", "2"], key3: "value3" }
      expect(JsonTools.recursive_merge(input1, input2)).to eq(expected)
    end
  end
end # RSpec.describe
