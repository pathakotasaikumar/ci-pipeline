$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib/util"))
require 'user_data.rb'

RSpec.describe UserData do
  before(:context) do
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))
  end

  include_examples "shared context"

  context '.process_file' do
    it 'returns empty string for empty file' do
      test_file_name = 'test-empty.txt'

      out_file = File.new("#{TEST_DATA_DIR}/#{test_file_name}", "w")
      out_file.close

      actual_result = UserData.process_file(
        "#{TEST_DATA_DIR}/#{test_file_name}",
        @test_data['Variables03']
      )

      File.delete(out_file)

      expect(actual_result).to eq('')
    end

    it 'returns string for content file' do
      test_file_name = 'test-replaced-vars.txt'

      out_file = File.new("#{TEST_DATA_DIR}/#{test_file_name}", "w")
      out_file.puts('REGION="<| Region |>"')
      out_file.puts('COUNTRY="<| Country |>"')
      out_file.close

      actual_result = UserData.process_file(
        "#{TEST_DATA_DIR}/#{test_file_name}",
        {
          'Region' => 'NSW',
          'Country' => 'Australia'
        }
      )

      File.delete(out_file)

      expect(actual_result).to eq('REGION="NSW"' + "\n" + 'COUNTRY="Australia"' + "\n")
    end
  end

  context '._process_text' do
    it 'returns array with json parsed with in' do
      expect(UserData._process_text(@test_data["Input01"], @test_data['Variables01'])).to eq @test_data["Result01"]
      expect(UserData._process_text(@test_data["Input02"], @test_data['Variables02'])).to eq @test_data["Result02"]
    end
  end

  context '.load_aws_userdata' do
    it 'returns hash with json parsed with in' do
      out_file = File.new("#{TEST_DATA_DIR}/test.txt", "w")
      out_file.puts(@test_data["Input03A"])
      out_file.puts(@test_data["Input03B"])
      out_file.close

      actual_result = UserData.load_aws_userdata("#{TEST_DATA_DIR}/test.txt", @test_data['Variables03'])

      File.delete(out_file)

      expect(@test_data["Result03"]).to eq(actual_result)
    end
  end
end # RSpec.describe
