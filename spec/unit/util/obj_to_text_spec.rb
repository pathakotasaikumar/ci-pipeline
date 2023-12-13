$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib/util"))
require 'obj_to_text.rb'

RSpec.describe ObjToText do
  before(:context) do
    @test_data = {
      {
        "xx_a" => "1",
        "xx_b" => 2,
        "xx_c" => 3,
        "xx_array" => [1, 2, 3, 4],
        "xx_obejct" => { "name" => "name_value" }
      } => [
        "xx_a=1",
        "xx_b=2",
        "xx_c=3",
        "xx_array=1,2,3,4",
        "xx_obejct={\\\"name\\\":\\\"name_value\\\"}"
      ].join("\n") + "\n",

    }
  end

  context '.generate_flat_config' do
    it 'returns flat config' do
      @test_data.keys.each do |key|
        test_data = key
        expected_data = @test_data[key]

        result = ObjToText.generate_flat_config(variables: test_data)
        expect(result).to eq(expected_data)
      end
    end

    it 'returns flat config with prefix' do
      prefix = "test-1-2-3"

      @test_data.keys.each do |key|
        test_data = key
        expected_data = @test_data[key].gsub("xx_", prefix + "xx_")

        result = ObjToText.generate_flat_config(
          variables: test_data,
          line_prefix: prefix
        )
        expect(result).to eq(expected_data)
      end
    end

    it 'returns replaced values' do
      local_test_data = {
        {
          'test-1' => '1',
          'TEST-2' => '2',
          '003' => '3',
          '004-1' => '4',
          '005--1' => '5',
          '-' => '6',
          '--' => '7'
        } => [
          'test_1=1',
          'TEST_2=2',
          '003=3',
          '004_1=4',
          '005__1=5',
          '_=6',
          '__=7'
        ].join("\n") + "\n"
      }

      local_test_data.keys.each do |key|
        test_data = key
        expected_data = local_test_data[key]

        result = ObjToText.generate_flat_config(
          variables: test_data
        )
        expect(result).to eq(expected_data)
      end
    end

    it 'returns quote_strings values' do
      local_test_data = {
        {
          'test-1' => '1',
          'TEST-2' => 2,
          '003' => '3',
          '004-1' => 4,
          '005--1' => '5',
          '-' => 6,
          '--' => '7',
          'arr' => [1, 2, 3],
          'arr_string' => ["1", 3, "5"]
        } => [
          'test_1="1"',
          'TEST_2="2"',
          '003="3"',
          '004_1="4"',
          '005__1="5"',
          '_="6"',
          '__="7"',
          'arr="1,2,3"',
          'arr_string="1,3,5"'
        ].join("\n") + "\n"
      }

      local_test_data.keys.each do |key|
        test_data = key
        expected_data = local_test_data[key]

        result = ObjToText.generate_flat_config(
          variables: test_data,
          quote_strings: true
        )
        expect(result).to eq(expected_data)
      end
    end

    it 'returns quote_strings values' do
      local_test_data = {
        {
          'test-1' => '1',
          'TEST-2' => 2,
          '003' => '3',
          '004-1' => 4,
          '005--1' => '5',
          '-' => 6,
          '--' => '7',
          'arr' => [1, 2, 3],
          'arr_string' => ["1", 3, "5"],
          'text' => 'test1 test 2 test 3',
          'special text' => '"test1" "test2"'
        } => [
          'test_1=1',
          'TEST_2=2',
          '003=3',
          '004_1=4',
          '005__1=5',
          '_=6',
          '__=7',
          'arr=1,2,3',
          'arr_string=1,3,5',
          'text="test1 test 2 test 3"',
          'special_text="\"test1\" \"test2\""'
        ].join("\n") + "\n"
      }

      local_test_data.keys.each do |key|
        test_data = key
        expected_data = local_test_data[key]

        result = ObjToText.generate_flat_config(
          variables: test_data,
          quote_strings: :special
        )
        expect(result).to eq(expected_data)
      end
    end

    it 'flatten hash values' do
      local_test_data = {
        {
          'test-1' => '1',
          'TEST-2' => 2,
          'a' => { 'test' => 'asd' }
        } => [
          'test_1=1',
          'TEST_2=2',
          'a_test=asd'
        ].join("\n") + "\n"
      }

      local_test_data.keys.each do |key|
        test_data = key
        expected_data = local_test_data[key]

        result = ObjToText.generate_flat_config(
          variables: test_data,
          quote_strings: :special,
          flat_hash_config: true
        )
        expect(result).to eq(expected_data)
      end
    end

    it 'fails on non-hash values' do
      expect {
        ObjToText.generate_flat_config(variables: "test")
      }.to raise_error(/Expecting a Hash, but received/)
    end
  end
end # RSpec.describe
