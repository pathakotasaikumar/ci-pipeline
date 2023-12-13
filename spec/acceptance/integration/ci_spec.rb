$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/test/api"))

require 'bamboo_client'
require 'rake'

RSpec.describe 'CI workflow' do
  before(:context) do
    # @log = ""
    # @error_flag = false
    # @files_downloaded = Array.new()
    # @list_of_uploaded_files = Array.new()

    # RSpec::Mocks.with_temporary_scope do
    #   allow(Log).to receive(:info)  { |arg| @log << "\nINFO : #{arg}" }
    #   allow(Log).to receive(:debug) { |arg| @log << "\nDEBUG : #{arg}" }
    #   allow(Log).to receive(:warn)  { |arg| @log << "\nWARN : #{arg}" }
    #   allow(Log).to receive(:error) { |arg| @error_flag = true , @log << "\nERROR : #{arg}" }
    #   Dir.chdir("#{TEST_DATA_DIR}/ciw-678") do
    #     load File.expand_path("#{BASE_DIR}/tasks/upload.rake", __FILE__)
    #     begin
    #       Rake::Task['upload:all'].reenable
    #       Rake::Task["upload:all"].invoke
    #     end
    #   end
    #   RSpec::Mocks.space.proxy_for(Log).reset
    # end
    # puts "Below are the logs collected during upload test execution: \n#{@log}"
    # @list_of_uploaded_files,@files_downloaded = parse_log_for_uploads_v2 @log
    # p "@list_of_uploaded_files.size: #{@list_of_uploaded_files.size}"
    # p "@files_downloaded.size: #{@files_downloaded.size}"
  end

  # context '- When Test APP CI build is successful' do

  #   it '- Then - CIW-6 - Test App artefacts are available in s3 dev' do
  #     expect(@files_downloaded.size).to eq(@list_of_uploaded_files.size)
  #     expect(@list_of_uploaded_files.size).to be > 0
  #   end

  #   it '- Then - CIW-7 - Test App CI build does not have any error flags' do
  #      expect(@error_flag).to eq false
  #   end

  #   it '- Then - CIW-8 - Checksum is generated for each uploaded entity' do
  #     expect(@files_downloaded.empty?).to eq(false)
  #     # checksum verification is internally done in @helper.s3_get_object
  #   end
  # end

  context '- When Test APP fails in pkg upload rake task' do
    it '- Then - CIW-3 - Error is notified'  do
      expect {
        begin
          Dir.chdir("#{TEST_DATA_DIR}/ciw-3") do
            load File.expand_path("#{BASE_DIR}/tasks/upload.rake", __FILE__)
            Rake::Task['upload:package'].reenable
            Rake::Task['upload:compliance'].reenable
            Rake::Task['upload:checksum'].reenable
            Rake::Task['upload:upload'].reenable
            Rake::Task['upload:clean'].reenable
            Rake::Task['upload:package'].invoke
            Rake::Task['upload:compliance'].invoke
            Rake::Task['upload:checksum'].invoke
            Rake::Task['upload:upload'].invoke
            Rake::Task['upload:clean'].invoke
          end
        end
      }.to raise_error(RuntimeError)
    end
  end
end
