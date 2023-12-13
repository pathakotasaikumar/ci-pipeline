$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/test/api"))
require 'bamboo_client'

def load_mocks mocks
  # Accepts array of
  # - Object: AwsInstance
  #   AnyInstance: To support mocking all objects of a class.
  #   Messages: receive_messages accepts input in hash form (req,res pairs) and doesnt require .and_return
  #   MessageChain: receive_message and receive_message_chain acceptns inputs in same way

  mocks.each { |mock|
    mocker = ""
    allow_type = ""
    receive_type = ""
    message_type = ""

    if mock.has_key?"AnyInstance"
      allow_type = 'expect_any_instance_of'
    else
      allow_type = 'allow'
    end

    if mock.has_key? "MessageChain"
      message_type = 'MessageChain'
      receive_type = 'receive_message_chain'
    end

    if mock.has_key? "Messages"
      message_type = 'Messages'
      receive_type = 'receive_messages'
    end

    mocker = "#{allow_type}(Kernel.const_get(mock['Object'])).to #{receive_type}(mock['#{message_type}'])"
    if message_type != 'Messages'
      mocker = mocker << " .and_return(mock['Return'])"
    end

    begin
      eval mocker
      Log.debug "mocker : #{mocker}".gsub!("mock['Object']", "#{mock['Object']}")
        .gsub!("mock['MessageChain']", "#{mock['MessageChain']}")
                                    .gsub!("mock['Return']", "#{mock['Return']}")
    rescue
    end
  } if mocks.nil? == false
end

def get_branch_pipeversion
  dev_branch_under_test = ENV["bamboo_planRepository_branch"]
  bamboo_client_cd = BambooClient.new("DEV-BAMBOO-CD")
  bamboo_client_cd.set_project_plan(ENV['bamboo_planKey'].split('-').first, ENV['bamboo_planKey'].split('-').last)
  core_log = bamboo_client_cd.get_build_logs(ENV['bamboo_buildNumber'], 'PU')
  core_log.each_line do |line|
    if line.include?"=> versions file uploaded"
      pipeline_info = eval(line[line.index('{')..line.index('}')])
      @pipeline_version_under_test = pipeline_info["pipeline.tar.gz"]
      break
    end
  end
  return dev_branch_under_test, @pipeline_version_under_test
end

def kick_off_build_and_get_result bamboo_client, project, plan, jobkey_to_log, plan_overrides = nil
  bamboo_client.set_project_plan(project, plan)
  new_build_number = bamboo_client.build_plan(plan_overrides)
  bamboo_client.poll_until_complete
  build_result = bamboo_client.get_build_result(new_build_number)
  if jobkey_to_log.nil?
    log = ""
  else
    log = bamboo_client.get_build_logs(new_build_number, jobkey_to_log)
  end
  return log, build_result
end

def parse_log_for_uploads log
  @files_downloaded = Array.new()
  @list_of_uploaded_files = Array.new()
  log.each_line do |line|
    # download files and read checksum
    if line.include? "=> versions file uploaded"
      @list_of_uploaded_files = eval(line[line.index('{')..line.index('}')])
      @list_of_uploaded_files.each do |key, version_id|
        file = AwsHelper.s3_get_object('cf-core-pipeline-dev', "master/" + key, version_id)
        @files_downloaded.push(file)
      end
      break
    end
  end
  return @list_of_uploaded_files, @files_downloaded
end

def parse_log_for_uploads_v2 log
  @files_downloaded = Array.new()
  @list_of_uploaded_files = Array.new()
  log.each_line do |line|
    # download files and read checksum
    if line.include? "Uploading object to S3"
      puts "Uploading log found \n #{line}"
      bucket, artefact = line.match(/"([^"]*)"/).to_s.gsub!("\"", "").strip.split('/', 2)
      puts "Downloading #{bucket}/#{artefact} for test verification"
      file = AwsHelper.s3_get_object(bucket, artefact)
      @list_of_uploaded_files.push("#{bucket}/#{artefact}")
      @files_downloaded.push(file)
    end
  end
  return @list_of_uploaded_files, @files_downloaded
end

def parse_log_for_consumed_pipever log
  log.each_line do |line|
    # read consumed pipeline version
    if line.include? "Retrieved pipeline artefact: master/pipeline.tar.gz at version:"
      @consumed_pipeline_version = line.split(' ').last
      break
    end
  end
  return @consumed_pipeline_version
end

def get_latest_pipeline_version
  object, _latest_pipeline_version = AwsHelper.s3_get_object('cf-core-pipeline', "master/pipeline.tar.gz")
  return _latest_pipeline_version
end

def cleanup_kms_stack
  Log.info "Attempting to cleanup old kms stack"
  unless AwsHelper.cfn_stack_exists(Defaults.kms_stack_name).nil?
    AwsHelper.cfn_delete_stack(Defaults.kms_stack_name)
  end
end

class DummyClass
  attr_accessor :definition
end
