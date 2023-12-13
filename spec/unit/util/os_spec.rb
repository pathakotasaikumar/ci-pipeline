$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib/util"))

require 'os.rb'

RSpec.describe Util::OS do
  before(:context) do
    @win_test_data = {
      [
        "cygwin",
        "mswin",
        "mingw",
        "bccwin",
        "wince",
        "emx"
      ] => true,
      [
        "win",
        "windows",
        "linux"
      ] => false
    }

    @mac_test_data = {
      [
        "darwin"
      ] => true,
      [
        "win",
        "windows",
        "linux"
      ] => false
    }

    @linux_test_data = {
      [
        "linux"
      ] => true
    }
  end

  context 'os' do
    it '.windows? parameters' do
      expect { Util::OS.windows? }.not_to raise_exception
      expect { Util::OS.windows?("11") }.not_to raise_exception

      expect { Util::OS.windows?(nil) }.to raise_exception(RuntimeError, /ruby_platform should not be nil/)
      expect { Util::OS.windows?(1) }.to raise_exception(RuntimeError, /should be a string/)
      expect { Util::OS.windows?({ '1' => 2 }) }.to raise_exception(RuntimeError, /should be a string/)
      expect { Util::OS.windows?([1, 2]) }.to raise_exception(RuntimeError, /should be a string/)
    end

    it '.windows? works' do
      @win_test_data.keys.each do |key|
        data_values = key
        expected_result = @win_test_data[key]

        data_values.each do |data|
          expect(Util::OS.windows?(data)).to be(expected_result)
        end
      end
    end

    it '.mac? parameters' do
      expect { Util::OS.mac? }.not_to raise_exception
      expect { Util::OS.mac?("11") }.not_to raise_exception

      expect { Util::OS.mac?(nil) }.to raise_exception(RuntimeError, /ruby_platform should not be nil/)
      expect { Util::OS.mac?(1) }.to raise_exception(RuntimeError, /should be a string/)
      expect { Util::OS.mac?({ '1' => 2 }) }.to raise_exception(RuntimeError, /should be a string/)
      expect { Util::OS.mac?([1, 2]) }.to raise_exception(RuntimeError, /should be a string/)
    end

    it 'mac? works' do
      @mac_test_data.keys.each do |key|
        data_values = key
        expected_result = @mac_test_data[key]

        data_values.each do |data|
          expect(Util::OS.mac?(data)).to be(expected_result)
        end
      end
    end

    it '.unix?' do
      # mac positive
      @mac_test_data.keys.each do |key|
        expected_result = @mac_test_data[key]
        next if expected_result == false

        data_values = key

        data_values.each do |data|
          expect(Util::OS.unix?(data)).to be(true)
        end
      end

      # win negative
      @win_test_data.keys.each do |key|
        expected_result = @win_test_data[key]

        next if expected_result == false

        data_values = key
        data_values.each do |data|
          expect(Util::OS.unix?(data)).to be(false)
        end
      end
    end

    it '.unix? parameters' do
      expect { Util::OS.unix? }.not_to raise_exception
      expect { Util::OS.unix?("11") }.not_to raise_exception

      expect { Util::OS.unix?(nil) }.to raise_exception(RuntimeError, /ruby_platform should not be nil/)
      expect { Util::OS.unix?(1) }.to raise_exception(RuntimeError, /should be a string/)
      expect { Util::OS.unix?({ '1' => 2 }) }.to raise_exception(RuntimeError, /should be a string/)
      expect { Util::OS.unix?([1, 2]) }.to raise_exception(RuntimeError, /should be a string/)
    end

    it '.linux?' do
      # mac negative
      @mac_test_data.keys.each do |key|
        expected_result = @mac_test_data[key]
        next if expected_result == false

        data_values = key

        data_values.each do |data|
          expect(Util::OS.linux?(data)).to be(false)
        end
      end

      # win negative
      @win_test_data.keys.each do |key|
        expected_result = @win_test_data[key]

        next if expected_result == false

        data_values = key
        data_values.each do |data|
          expect(Util::OS.linux?(data)).to be(false)
        end
      end

      # linux positive
      @linux_test_data.keys.each do |key|
        expected_result = @linux_test_data[key]
        data_values = key
        data_values.each do |data|
          expect(Util::OS.linux?(data)).to be(expected_result)
        end
      end
    end

    it '.linux? parameters' do
      expect { Util::OS.linux? }.not_to raise_exception
      expect { Util::OS.linux?("11") }.not_to raise_exception

      expect { Util::OS.linux?(nil) }.to raise_exception(RuntimeError, /ruby_platform should not be nil/)
      expect { Util::OS.linux?(1) }.to raise_exception(RuntimeError, /should be a string/)
      expect { Util::OS.linux?({ '1' => 2 }) }.to raise_exception(RuntimeError, /should be a string/)
      expect { Util::OS.linux?([1, 2]) }.to raise_exception(RuntimeError, /should be a string/)
    end
  end
end
