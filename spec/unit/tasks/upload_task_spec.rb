$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib"))
require 'tasks/upload_task.rb'
require 'component'
require 'component_validator'
require 'util/yaml_include'
require 'util/archive'
require 'util/stat_helper'
require 'tmpdir'

RSpec.describe UploadTask do
  def _get_task
    result = UploadTask.new

    result.validation_mode = "enforce"
    result.use_custom_validation = false

    result
  end

  context '.instantiate' do
    it 'can create an instance' do
      task = _get_task

      expect(task).not_to eq(nil)
    end
  end

  context '.name' do
    it 'returns value' do
      task = _get_task

      expect(task.name).to eq("upload")
    end
  end

  context '._env' do
    it 'returns value' do
      task = _get_task

      expect(task.send(:_env)).to eq(ENV)
    end
  end

  context '.compliance' do
    it 'does nothing' do
      task = _get_task

      expect { task.compliance }.not_to raise_error
    end
  end

  context '.checksum' do
    it 'does nothing' do
      task = _get_task

      expect { task.checksum }.not_to raise_error
    end
  end

  context '.prepare' do
    it 'prepares PROD environment' do
      task = _get_task

      env = {}

      allow(task).to receive(:_env).and_return(env)
      expect { task.prepare }.not_to raise_error

      expect(env['APP_DIR'].end_with?('/app')).to eq(true)
      expect(env['PAYLOAD_BASE_DIR'].end_with?('/payload')).to eq(true)
      expect(env['PLATFORM_DIR'].end_with?('/app/platform')).to eq(true)
    end

    it 'prepares DEV environment' do
      task = _get_task

      env = {
        'local_dev' => 'true'
      }

      allow(FileUtils).to receive(:mkdir_p)
      allow(FileUtils).to receive(:copy_entry)

      allow(task).to receive(:_env).and_return(env)
      expect { task.prepare }.not_to raise_error

      expect(env['local_dev']).to eq("true")
      expect(env['APP_DIR'].end_with?('/app')).to eq(true)
      expect(env['PAYLOAD_BASE_DIR'].end_with?('/payload')).to eq(true)
      expect(env['PLATFORM_DIR'].end_with?('/app/platform')).to eq(true)
    end
  end

  context '.validate' do
    it 'calls .prepare' do
      task = _get_task

      allow(task).to receive(:prepare)
      expect(task).to receive(:prepare).once

      env = {
        'PLATFORM_DIR' => "#{BASE_DIR}/platform"
      }

      allow(task).to receive(:_env).and_return(env)
      allow(task).to receive(:prepare)

      task.validation_mode = 'not_enforce'

      expect { task.validate }.not_to raise_error
    end

    it 'validates components, custom validation mode' do
      task = _get_task

      env = {
        'PLATFORM_DIR' => "#{BASE_DIR}/platform"
      }

      allow(task).to receive(:_env).and_return(env)
      allow(task).to receive(:prepare)

      task.validation_mode = 'not_enforce'
      task.use_custom_validation = true

      expect { task.validate }.not_to raise_error
    end

    it 'validates components, regular mode' do
      task = _get_task

      env = {
        'PLATFORM_DIR' => "#{BASE_DIR}/platform"
      }

      allow(task).to receive(:_env).and_return(env)
      allow(task).to receive(:prepare)

      task.validation_mode = 'not_enforce'

      expect { task.validate }.not_to raise_error
    end

    it 'does not raise on error, regular mode' do
      task = _get_task

      env = {
        'PLATFORM_DIR' => "#{BASE_DIR}/platform"
      }

      allow(task).to receive(:_env).and_return(env)
      allow(task).to receive(:prepare)

      allow(Context).to receive_message_chain('environment.variable')
        .and_raise('cannot run validation')

      expect { task.validate }.not_to raise_error
    end

    it 'does not raise on failured validation, regular mode' do
      task = _get_task

      env = {
        'PLATFORM_DIR' => "#{BASE_DIR}/platform"
      }

      allow(task).to receive(:_env).and_return(env)
      allow(task).to receive(:prepare)

      task.validation_mode = ""
      allow(task).to receive(:validate_component).and_return(false)

      expect { task.validate }.not_to raise_error
    end

    it 'validates components, enforce mode' do
      task = _get_task

      env = {
        'PLATFORM_DIR' => "#{BASE_DIR}/platform"
      }

      allow(task).to receive(:_env).and_return(env)
      allow(task).to receive(:prepare)

      task.validation_mode = 'enforce'

      allow(task).to receive(:validate_component).and_return(false)

      allow_any_instance_of(ComponentValidator).to receive(:last_errors).and_return(["error1"])
      allow_any_instance_of(ComponentValidator).to receive(:last_warnings).and_return(["warning1"])

      expect { task.validate }.to raise_error(/Component validation has failed and mode is set to/)
    end

    it 'raises in failed components, enforce mode' do
      task = _get_task

      env = {
        'PLATFORM_DIR' => "#{BASE_DIR}/platform"
      }

      allow(task).to receive(:_env).and_return(env)
      allow(task).to receive(:prepare)

      task.validation_mode = 'enforce'

      allow(task).to receive(:validate_component).and_raise("cannot validate components")

      allow_any_instance_of(ComponentValidator).to receive(:last_errors).and_return(["error1"])
      allow_any_instance_of(ComponentValidator).to receive(:last_warnings).and_return(["warning1"])

      expect { task.validate }.to raise_error(/Component validation has encountered an error/)
    end
  end

  context '.validate_component' do
    it 'validates components' do
      task = _get_task

      validator = ComponentValidator.new(
        "#{BASE_DIR}/lib/validation_specs/cloudformation",
        "#{BASE_DIR}/lib/validation_specs/component"
      )

      expect {
        Dir[File.join("#{BASE_DIR}/platform", '*.yaml')].each do |component_file|
          component_name = File.basename(component_file, '.yaml')
          definition = YAML.load_file(component_file)

          # emulating errors and warnings
          allow(validator).to receive(:errors).and_return(['e1', 'e2'])
          allow(validator).to receive(:warnings).and_return(['w1', 'w2'])

          component_result = task.validate_component(validator, component_name, definition)
        end
      }.not_to raise_error
    end
  end

  context '.clean' do
    it 'cleans' do
      task = _get_task

      allow(FileUtils).to receive(:rm_rf)

      expect {
        task.clean
      }.not_to raise_error
    end

    it 'raises error on fail' do
      task = _get_task

      allow(FileUtils).to receive(:rm_rf).and_raise('Cannot delete files')

      expect {
        task.clean
      }.to raise_error(/Cannot delete files/)
    end
  end

  context '.package' do
    it 'packages components' do
      task = _get_task

      test_data_dir =

        env = {
          'PLATFORM_DIR' => "#{BASE_DIR}/platform",
          'APP_DIR' => "#{BASE_DIR}",
          'COMPONENT_DIR' => Dir.mktmpdir,
          'PAYLOAD_BASE_DIR' => Dir.mktmpdir,
          'PAYLOAD_DIR' => Dir.mktmpdir
        }

      allow(FileUtils).to receive(:chmod)

      # skipping YAML file override!
      allow(File).to receive(:write)

      allow(Util::Archive).to receive(:gzip!)
      allow(Util::Archive).to receive(:tar!)

      allow(AwsHelper).to receive(:ecr_repository_exists?).and_return(true)
      allow(AwsHelper).to receive(:ecr_set_repository_policy) 
      allow(AwsHelper).to receive(:ecr_get_authorisation_token).and_return('ecr_auth_token') 

      allow(task).to receive(:_env).and_return(env)

      allow_any_instance_of(Kernel).to receive(:system).and_return(true)

      expect {
        component_result = task.package
      }.not_to raise_error
    end

    it 'packraises on script execution error' do
      task = _get_task

      env = {
        'PLATFORM_DIR' => "#{BASE_DIR}/platform",
        'APP_DIR' => "#{BASE_DIR}",
        'COMPONENT_DIR' => Dir.mktmpdir,
        'PAYLOAD_BASE_DIR' => Dir.mktmpdir,
        'PAYLOAD_DIR' => Dir.mktmpdir
      }

      allow(FileUtils).to receive(:chmod)
      # skipping YAML file override!
      allow(File).to receive(:write)

      allow(Util::Archive).to receive(:gzip!)
      allow(Util::Archive).to receive(:tar!)

      allow(task).to receive(:_env).and_return(env)

      allow_any_instance_of(Kernel).to receive(:system).and_return(false)

      expect {
        component_result = task.package
      }.to raise_error(/FAILED to execute script/)
    end
  end

  context '.upload' do
    it 'uploads components' do
      task = _get_task

      env = {
        'PLATFORM_DIR' => "#{BASE_DIR}/platform",
        'APP_DIR' => "#{BASE_DIR}",
        'COMPONENT_DIR' => Dir.mktmpdir,
        'PAYLOAD_BASE_DIR' => Dir.mktmpdir,
        'PAYLOAD_DIR' => Dir.mktmpdir
      }

      allow(task).to receive(:_env).and_return(env)

      allow(FileUtils).to receive(:chmod)
      # skipping YAML file override!
      allow(File).to receive(:write)

      # allow(Context).to receive_message_chain('s3.artefact_bucket_name')
      # allow(Defaults).to receive_message_chain('s3.artefact_bucket_name')

      allow(AwsHelper).to receive(:s3_delete_objects)
      allow(AwsHelper).to receive(:s3_upload_file)

      allow(task).to receive(:clean)

      expect {
        component_result = task.upload
      }.not_to raise_error
    end

    it 'raises om upload error' do
      task = _get_task

      env = {
        'PLATFORM_DIR' => "#{BASE_DIR}/platform",
        'APP_DIR' => "#{BASE_DIR}",
        'COMPONENT_DIR' => Dir.mktmpdir,
        'PAYLOAD_BASE_DIR' => Dir.mktmpdir,
        'PAYLOAD_DIR' => Dir.mktmpdir
      }

      allow(task).to receive(:_env).and_return(env)

      allow(FileUtils).to receive(:chmod)
      # skipping YAML file override!
      allow(File).to receive(:write)

      allow(Context).to receive_message_chain('s3.artefact_bucket_name')
        .and_raise('Cannot upload files')

      allow(AwsHelper).to receive(:s3_delete_objects)
      allow(AwsHelper).to receive(:s3_upload_file)

      allow(task).to receive(:clean)

      expect {
        component_result = task.upload
      }.to raise_error(/Cannot upload files/)
    end
  end

  context 'scan' do
    it 'executes scan task' do
      task = _get_task

      env = {
        'PLATFORM_DIR' => "#{BASE_DIR}/platform",
        'APP_DIR' => "#{BASE_DIR}",
        'COMPONENT_DIR' => Dir.mktmpdir,
        'PAYLOAD_BASE_DIR' => Dir.mktmpdir,
        'PAYLOAD_DIR' => Dir.mktmpdir
      }

      allow(task).to receive(:_env).and_return(env)

      allow(Pipeline::Helpers::Veracode).to receive(:load_config).and_return(crit: 'Medium')
      mock_veracode_client = double(Pipeline::Helpers::Veracode)
      allow((Pipeline::Helpers::Veracode)).to receive(:new).and_return(mock_veracode_client)
      allow(mock_veracode_client).to receive(:enabled?).and_return(true)
      allow(mock_veracode_client).to receive(:package).and_return(nil)
      allow(mock_veracode_client).to receive(:upload).and_return(nil)
      allow(mock_veracode_client).to receive(:run).and_return(nil)

      expect { task.scan }.not_to raise_error
    end
  end

  context 'cdintegration' do
    it 'does nothing without variable' do
      task = _get_task
      allow(Defaults).to receive(:invoke_bamboocd_enable).and_return(nil)
      expect { task.cdintegration }.to output(/Bamboo plan variable \"invoke_bamboocd_enable\" is not set/).to_stdout
    end

    it 'does nothing with disabled' do
      task = _get_task
      allow(Defaults).to receive(:invoke_bamboocd_enable).and_return("DISABLED")
      expect { task.cdintegration }.to output(/explicitly set to disabled/).to_stdout
    end

    it 'does nothing with prod' do
      task = _get_task
      allow(Defaults).to receive(:invoke_bamboocd_enable).and_return("true")
      allow(Defaults).to receive(:invoke_bamboocd_ase).and_return("prod")
      expect { task.cdintegration }.to output(/only non-prod environments supported/).to_stderr
    end

    it 'handles http helper exceptions' do
      task = _get_task
      allow(Defaults).to receive(:invoke_bamboocd_enable).and_return("true")
      allow(Defaults).to receive(:bamboo_cd_api_baseurl).and_return("https://test.invalid/")
      expect { task.cdintegration }.to output(/Exception encountered while attempting to invoke Bamboo CD plan/).to_stderr
    end

    it 'handles a bad uri' do
      ENV['bamboo_baseurl_bamboo_cd_api'] || skip('Skipping CD Integration due to not being on Bamboo')
      task = _get_task
      allow(Defaults).to receive(:invoke_bamboocd_enable).and_return("true")
      allow(Defaults).to receive(:invoke_bamboocd_ase).and_return("INVALID")
      allow(Defaults).to receive(:plan_key).and_return("AMSxx-PxxSxxCI0")
      allow(Defaults).to receive(:branch).and_return("xxx")
      expect { task.cdintegration }.to output(/Bamboo CD responded with status code/).to_stderr
    end

    it 'successfully calls cd deploy stage' do
      ENV['bamboo_baseurl_bamboo_cd_api'] || skip('Skipping CD Integration due to not being on Bamboo')
      task = _get_task
      allow(Defaults).to receive(:plan_key).and_return("AMS01-C031S06CI")
      allow(Defaults).to receive(:invoke_bamboocd_enable).and_return("true")
      allow(Defaults).to receive(:branch).and_return("master")
      expect { task.cdintegration }.to output(/Bamboo CD plan was successfully invoked/).to_stdout
    end

    it 'successfully calls cd release stage' do
      ENV['bamboo_baseurl_bamboo_cd_api'] || skip('Skipping CD Integration due to not being on Bamboo')
      task = _get_task
      allow(Defaults).to receive(:invoke_bamboocd_stage).and_return("Release")
      allow(Defaults).to receive(:plan_key).and_return("AMS01-C031S06CI")
      allow(Defaults).to receive(:invoke_bamboocd_enable).and_return("true")
      allow(Defaults).to receive(:branch).and_return("master")
      expect { task.cdintegration }.to output(/Bamboo CD plan was successfully invoked/).to_stdout
    end
  end

  context '.all' do
    it 'executes flow' do
      task = _get_task

      allow(task).to receive(:prepare)
      allow(task).to receive(:validate)
      allow(task).to receive(:package)
      allow(task).to receive(:compliance)
      allow(task).to receive(:checksum)
      allow(task).to receive(:upload)
      allow(task).to receive(:scan)
      allow(task).to receive(:clean)
      allow(task).to receive(:cdintegration)

      allow(Log).to receive(:splunk_http)
      allow(Log).to receive(:warn)

      allow(StatHelper).to receive(:start_pipeline_stage)
      allow(StatHelper).to receive(:finish_pipeline_stage)

      expect {
        component_result = task.all
      }.not_to raise_error
    end

    it 'does not raise on finish_pipeline_stage error' do
      task = _get_task

      allow(task).to receive(:prepare)
      allow(task).to receive(:validate)
      allow(task).to receive(:package)
      allow(task).to receive(:compliance)
      allow(task).to receive(:checksum)
      allow(task).to receive(:upload)
      allow(task).to receive(:scan)
      allow(task).to receive(:clean)
      allow(task).to receive(:cdintegration)

      allow(Log).to receive(:splunk_http)
      allow(Log).to receive(:warn)

      allow(StatHelper).to receive(:start_pipeline_stage)
      allow(StatHelper).to receive(:finish_pipeline_stage).and_raise('cannot use splunk')

      expect {
        component_result = task.all
      }.not_to raise_error
    end

    it 'does not raise on start_pipeline_stage error' do
      task = _get_task

      allow(task).to receive(:prepare)
      allow(task).to receive(:validate)
      allow(task).to receive(:package)
      allow(task).to receive(:compliance)
      allow(task).to receive(:checksum)
      allow(task).to receive(:upload)
      allow(task).to receive(:scan)
      allow(task).to receive(:clean)
      allow(task).to receive(:cdintegration)

      allow(Log).to receive(:splunk_http)
      allow(Log).to receive(:warn)

      allow(StatHelper).to receive(:start_pipeline_stage).and_raise('cannot use splunk')
      allow(StatHelper).to receive(:finish_pipeline_stage)

      expect {
        component_result = task.all
      }.not_to raise_error
    end

    it 'raises on upload error' do
      task = _get_task

      allow(task).to receive(:prepare).and_raise('Cannot prepare')
      allow(task).to receive(:validate)
      allow(task).to receive(:package)
      allow(task).to receive(:compliance)
      allow(task).to receive(:checksum)
      allow(task).to receive(:upload)
      allow(task).to receive(:scan)
      allow(task).to receive(:clean)
      allow(task).to receive(:cdintegration)

      allow(Log).to receive(:splunk_http)
      allow(Log).to receive(:warn)

      allow(StatHelper).to receive(:start_pipeline_stage).and_raise('cannot use splunk')
      allow(StatHelper).to receive(:finish_pipeline_stage)

      expect {
        component_result = task.all
      }.to raise_error(/Cannot prepare/)
    end
  end
end
