require 'service_container'
require 'component'
require 'runner'
require 'util/archive'
require 'core/app_container_info'
require_relative 'base_task.rb'
require_relative 'context_task.rb'
require 'validation/validation_service'
require 'core/app_container_info'
require 'pipeline/helpers/veracode'
require 'pipeline/helpers/http'
require 'json'

include Util::Archive

include Qantas::Pipeline
include Qantas::Pipeline::Core

class UploadTask < BaseTask
  @validation_result = {}
  @context_task

  attr_accessor :validation_mode
  attr_accessor :use_custom_validation

  def initialize
  end

  def validation_mode
    if @validation_mode.nil?
      @validation_mode = Defaults.pipeline_validation_mode
    end

    @validation_mode
  end

  def use_custom_validation
    if @use_custom_validation.nil?
      @use_custom_validation = Defaults.pipeline_use_custom_validation?
    end

    @use_custom_validation
  end

  def name
    "upload"
  end

  # @param [ComponentValidator] validator
  # @param [string] name
  # @param [string] definition
  def validate_component(validator, name, definition)
    validator.validate(name, definition)

    validator.errors.each do |message|
      Log.error "- #{message}"
    end

    validator.warnings.each do |message|
      Log.warn "- #{message}"
    end
    success = validator.errors.empty? and validator.warnings.empty?

    validator.reset()

    return success
  end

  def prepare
    # The directory structure is different between local_dev (docker) and agent
    # On the docker dev container
    #  - /build-dir/pipeline (current dir)
    #  - /build-dir/pipeline/payload
    #  - /build-dir/pipeline/scan
    #  - /build-dir/app (including platform)
    # On the real build agent
    #  - /build-dir
    #  - /build-dir/pipeline (current dir - in rake.sh)
    #  - /build-dir/app
    #  - /build-dir/payload
    #  - /build-dir/scan
    _env['BUILD_DIR'] = File.expand_path("..", Dir.pwd)
    _env['PIPELINE_DIR'] = File.join _env['BUILD_DIR'], 'pipeline'
    _env['APP_DIR'] = _env['APP_DIR'] || (File.join _env['BUILD_DIR'], 'app')
    _env['PLATFORM_DIR'] = File.join _env['APP_DIR'], 'platform'
    if _env['local_dev'] || _env['container_execution']
      _env['PAYLOAD_BASE_DIR'] = File.join _env['PIPELINE_DIR'], 'payload'
      _env['SCAN_DIR'] = File.join _env['PIPELINE_DIR'], 'scan'
    else
      _env['PAYLOAD_BASE_DIR'] = File.join _env['BUILD_DIR'], 'payload'
      _env['SCAN_DIR'] = File.join _env['BUILD_DIR'], 'scan'
    end

    # Add YAML custom domain types
    # Set $APP_DIR as the base directory for relative path access
    Util::YAMLInclude.yaml(_env['APP_DIR'])
    Util::YAMLInclude.json(_env['APP_DIR'])
    Util::YAMLInclude.text(_env['APP_DIR'])
    Util::YAMLInclude.xml(_env['APP_DIR'])

    FileUtils.mkdir_p _env['PAYLOAD_BASE_DIR']
    FileUtils.mkdir_p _env['SCAN_DIR']

    Log.info "Application Directories"
    Log.info " - local_dev: #{_env['local_dev']}"
    Log.info " - BUILD_DIR: #{_env['BUILD_DIR']}"
    Log.info " - APP_DIR: #{_env['APP_DIR']}"
    Log.info " - PLATFORM_DIR: #{_env['PLATFORM_DIR']}"
    Log.info " - PAYLOAD_BASE_DIR: #{_env['PAYLOAD_BASE_DIR']}"
  end

  def validate
    Defaults.set_pipeline_task('validate')

    prepare

    success = true
    validation_messages = []

    validation_hash = {
      :is_valid => false,
      :validation_mode => 'unknown',
      :messages => []
    }

    begin
      validation_hash[:validation_mode] = validation_mode

      if validation_mode == 'enforce'
        Log.output 'Component validation is set to ENFORCE mode. Validation errors will fail this build.'
      else
        Log.output 'Component validation is set to REPORT mode. Validation errors will not fail this build.'
      end

      validator = ComponentValidator.new(
        "#{BASE_DIR}/lib/validation_specs/cloudformation",
        "#{BASE_DIR}/lib/validation_specs/component"
      )

      validation_data = ValidationData.new

      # Load component definition
      Dir[File.join(_env['PLATFORM_DIR'], '*.yaml')].each do |component_file|
        component_name = File.basename(component_file, '.yaml')

        Log.output "Validating component #{component_name}"
        definition = YAML.load_file(component_file)

        component_result = validate_component(validator, component_name, definition)
        success = component_result && success

        unless component_result
          validator.last_errors.each do |validation_error|
            validation_messages << "[ERROR] - Component [#{component_name}] - [#{validation_error}]"
          end
          validator.last_warnings.each do |validation_error|
            validation_messages << "[WARNING] - Component [#{component_name}] - [#{validation_error}]"
          end
        end

        app_container_info = AppContainerInfo.new(sections: Defaults.sections)

        validation_data.add_component_info(
          app_container_info: app_container_info,
          component_file: component_file,
          component_name: component_name,
          component_hash: definition
        )

        environments = (definition['Environments'] || {}).keys

        environments.each do |environment|
          # Perform a deep merge of the component definition and the environment overrides
          branch = Defaults.sections[:branch]
          merger = proc { |key, v1, v2| Hash === v1 && Hash === v2 ? v1.merge(v2, &merger) : v2 }
          if environment.include?(branch)
            merged_definition = definition.merge(definition['Environments'][environment][branch].to_h, &merger)
          else
            merged_definition = definition.merge(definition['Environments'][environment].to_h, &merger)
          end

          Log.output "Validating component #{component_name} (Environment #{environment}) (Branch #{branch})"
          environment_result = validate_component(validator, component_name, merged_definition)
          success = environment_result && success

          # app_container_info override with new Environment
          env_sections = Marshal.load(Marshal.dump(Defaults.sections))
          env_sections[:env] = environment
          env_sections[:branch] = branch
          env_app_container_info = AppContainerInfo.new(sections: env_sections)

          validation_data.add_component_info(
            app_container_info: env_app_container_info,
            component_file: component_file,
            component_name: component_name,
            component_hash: merged_definition
          )

          unless component_result
            validator.last_errors.each do |validation_error|
              validation_messages << "[ERROR] - Component [#{component_name}] - Environment [#{environment}] - [#{validation_error}]"
            end
            validator.last_warnings.each do |validation_error|
              validation_messages << "[WARNING] - Component [#{component_name}] - Environment [#{environment}] - [#{validation_error}]"
            end
          end
        end
      end

      if use_custom_validation
        Log.output 'Running custom validation...'
        _execute_custom_validators(data: validation_data, validation_mode: validation_mode, validation_hash: validation_hash)
      else
        Log.output 'Skipping custom validation. Use "pipeline_custom_validation" flag to enable it'
      end
    rescue => e
      if validation_mode == 'enforce'
        Log.error e
        raise "Component validation has encountered an error, failing build - #{e.backtrace.join("\n")}"
      else
        Log.error e
        Log.error "Component validation has encountered an error, continuing build - #{e.backtrace.join("\n")}"
      end
    end

    validation_hash[:is_valid] = success
    validation_hash[:messages] = validation_messages unless validation_messages.empty?

    @validation_result = validation_hash

    if success
      Log.output 'Component validation completed successfully - no issues found'
    else
      if validation_mode == 'enforce'
        raise 'Component validation has failed and mode is set to ENFORCE, failing build.'
      else
        Log.error 'Component validation has failed but mode is set to REPORT, continuing build.'
      end
    end
  end

  def package
    Log.info "Packaging application components"
    begin
      # Execute build scripts for each component
      component_files = Dir[File.join(_env['PLATFORM_DIR'], '*.yaml')]
      component_files.each do |component_file|
        # Load files to act on any !include functions specified by users in yaml
        component_definition = YAML.load_file(component_file)
        File.write(component_file, YAML.dump(component_definition))
        component_name = File.basename(component_file, '.yaml')

        # Set environment variables
        _env['COMPONENT_DIR'] = File.join _env['APP_DIR'], 'platform', component_name
        _env['PAYLOAD_DIR'] = File.join _env['PAYLOAD_BASE_DIR'], component_name
        _env['PAYLOAD_CODEDEPLOY_DIR'] = File.join _env['PAYLOAD_BASE_DIR'], ('codedeploy/' + component_name)

        artefact_filename = File.join _env['PAYLOAD_BASE_DIR'], component_name + '.tar.gz'
        artefact_revision_filename = File.join _env['PAYLOAD_BASE_DIR'], component_name + '_codedeploy_revision.tar.gz'

        # Create the component payload directory
        FileUtils.mkdir_p _env['PAYLOAD_DIR']
        FileUtils.mkdir_p _env['PAYLOAD_CODEDEPLOY_DIR']

        build_scripts = %w(build.sh build.ps1 Dockerfile).map { |file|
          script = File.join(File.dirname(component_file), component_name, file)
          script if File.exist? script
        }.compact

        if build_scripts.any?
          Log.info "Executing build script for component #{component_name}"

          script_args = [
            _env['APP_DIR'],
            _env['COMPONENT_DIR'],
            _env['PAYLOAD_DIR']
          ]

          # Execute build scripts
          build_scripts.each do |script_file|
            FileUtils.chmod 0o755, script_file
            success = if script_file.end_with? '.sh'
                        system('sh', script_file, *script_args)
                      elsif script_file.end_with? '.ps1'
                        system('powershell -File', script_file, *script_args)
                      elsif script_file.end_with? 'Dockerfile'
                        docker_build(script_file, component_name)
                      else
                        raise "Unknown script type #{script_file}. Specify .sh or ps1 build script file"
                      end

            unless success
              raise "FAILED to execute script: #{script_file} - #{$CHILD_STATUS}"
            end
          end
        else
          Log.info "No build script found for component #{component_name.inspect}"
          Log.info "Component #{component_name.inspect} artefact will be empty"
        end

        # Create artefact tarball
        Log.info "Creating artefact for component #{component_name.inspect}"

        gzip!(tar!(_env['PAYLOAD_DIR']), artefact_filename)

        code_deploy_dir =  File.join _env['PAYLOAD_BASE_DIR'], ('codedeploy/' + component_name)
        Log.info "Creating codedeploy revision for component #{component_name.inspect}"

        if !Dir["#{code_deploy_dir}/*"].empty?
          is_windows_component = Defaults.codedeploy_win_component?(definition: component_definition)

          if is_windows_component
            artefact_revision_filename = File.join _env['PAYLOAD_BASE_DIR'], component_name + '_codedeploy_revision.zip'
          end

          Log.info "Packaging revision for component #{component_name.inspect}"

          if is_windows_component
            cmd = "cd #{code_deploy_dir} && zip -r #{artefact_revision_filename} *"
            Log.info "Packing windows zip revision with: #{cmd}"

            system("echo 'Checking zip presense'")
            which_zip_result = system('which zip')

            if which_zip_result != 0 && which_zip_result != true
              raise "Cannot find 'zip' command and pack CodeDeploy revision for windows - 'which zip' exit code was: #{which_zip_result}"
            end

            system(cmd)
          else
            gzip!(tar!(code_deploy_dir), artefact_revision_filename)
          end
        else
          Log.info "No codedeploy revision is found for component #{component_name.inspect}"
        end
      end

      # Create a components.tar.gz containing component definition files
      if component_files.empty?
        Log.warn "No component definitions were found - creating an empty component definition artefact"
        Log.debug "Packaging empty directory #{File.join(_env['PAYLOAD_BASE_DIR'], 'components.tar.gz')}"

        gzip!(
          tar!((Dir.mktmpdir 'pipeline_')),
          File.join(_env['PAYLOAD_BASE_DIR'], 'components.tar.gz')
        )

      else
        Log.info "Creating component definition artefact with #{component_files.size} component(s)"
        gzip!(
          tar(_env['PLATFORM_DIR'], 'components.tar', '*.yaml'),
          File.join(_env['PAYLOAD_BASE_DIR'], 'components.tar.gz')
        )
      end
    rescue => e
      Log.error "Failed to execute upload task - #{e}"
      clean
      raise
    end
  end

  def compliance
    Log.info 'perform compliance checks'
  end

  def checksum
    Log.info 'create checksum'
    Log.info 'log checksum to CMDB'
  end

  def upload
    begin
      bucket_name = Context.s3.artefact_bucket_name
      base_ci_path = Defaults.ci_artefact_path

      # Delete the current CI artefact directory
      AwsHelper.s3_delete_objects(bucket_name, base_ci_path)

      # Generate new CI variables metadata
      ci_vars = _env.select do |key, value|
        %w(
          bamboo_buildNumber
          bamboo_planKey
          bamboo_planRepository_branchName
          bamboo_repository_revision_number
          bamboo_resultsUrl
        ).include? key
      end

      # Upload artefact for each component
      Dir[File.join(_env['PLATFORM_DIR'], '*.yaml')].each do |component_filename|
        component_name = File.basename(component_filename, '.yaml')

        artefact_filename = File.join _env['PAYLOAD_BASE_DIR'], component_name + '.tar.gz'
        artefact_revision_filename_linux = File.join _env['PAYLOAD_BASE_DIR'], component_name + '_codedeploy_revision.tar.gz'
        artefact_revision_filename_win = File.join _env['PAYLOAD_BASE_DIR'], component_name + '_codedeploy_revision.zip'

        if File.exist? artefact_filename
          Log.debug "Application artefact found: #{artefact_filename}"
          Log.info "Uploading artefact for component #{component_name.inspect}"

          # Upload component artefact to ci artefact path
          artefact_s3_path = Defaults.ci_artefact_path(component_name: component_name)
          version = AwsHelper.s3_upload_file(
            bucket_name,
            "#{artefact_s3_path}/app.tar.gz",
            artefact_filename,
            ci_vars
          )
        else
          Log.info "No artefact found for component #{component_name.inspect}, skipping upload."
        end

        # uploading revision
        artefact_revision_filename = artefact_revision_filename_linux

        if File.exist? artefact_revision_filename_linux
          artefact_revision_filename = artefact_revision_filename_linux
        end

        if File.exist? artefact_revision_filename_win
          artefact_revision_filename = artefact_revision_filename_win
        end

        if File.exist? artefact_revision_filename
          Log.debug "Revision artefact found: #{artefact_revision_filename}"
          Log.info "Uploading revision artefact for component #{component_name.inspect}"

          # Upload component revision artefact to ci artefact path
          latest_artefact_revision_s3_path = Defaults.ci_artefact_path(component_name: component_name)
          versioned_artefact_revision_s3_path = Defaults.ci_versioned_artefact_path(component_name: component_name, build_number: ci_vars['bamboo_buildNumber'])

          revision_file_extension = "tar.gz"

          if File.exist? artefact_revision_filename_win
            revision_file_extension = "zip"
          end

          latest = AwsHelper.s3_upload_file(
            bucket_name,
            "#{latest_artefact_revision_s3_path}/revision.#{revision_file_extension}",
            artefact_revision_filename,
            ci_vars
          )
          version = AwsHelper.s3_upload_file(
            bucket_name,
            "#{versioned_artefact_revision_s3_path}/revision.#{revision_file_extension}",
            artefact_revision_filename,
            ci_vars
          )
        else
          Log.info "No revision artefact found for component #{component_name.inspect}, skipping upload."
        end
      end

      # Upload components.tar.gz
      artefact_filename = File.join _env['PAYLOAD_BASE_DIR'], 'components.tar.gz'

      # Upload components to ci artefact path
      artefact_s3_path = Defaults.ci_artefact_path
      Log.debug artefact_filename
      AwsHelper.s3_upload_file(
        bucket_name,
        "#{artefact_s3_path}/components.tar.gz",
        artefact_filename,
        ci_vars
      )
    rescue => e
      Log.error "Failed to execute upload task #{name} - #{e}"
      clean
      raise
    end
  end

  def scan
    veracode_config_file = File.join(_env['APP_DIR'], 'scan.yaml')

    if File.exist?(veracode_config_file)
      veracode_config = Pipeline::Helpers::Veracode.load_config(veracode_config_file)

      return if veracode_config.blank?

      veracode_scanner = Pipeline::Helpers::Veracode.new(
        branch: Defaults.branch,
        scan_dir: _env['SCAN_DIR'],
        config: veracode_config
      )

      return unless veracode_scanner.enabled?

      veracode_scanner.package
      veracode_scanner.upload
      veracode_scanner.run

    else
      Log.info "No Veracode config file found #{veracode_config_file}. Skipping"
    end
  rescue => e
    Log.error "Failed to execute Veracode upload & run tasks - #{e}"
  end

  def docker_build(script_file, component_name)

    ecr_registry = "#{Defaults.ecr_registry}"
    repository = "#{Defaults.ecr_repository_name(component_name)}"
    image_tag = "#{Defaults.ecr_latest_image_tag(component_name)}"

    docker_build_cmd = "docker build #{File.dirname(script_file)} -t #{ecr_registry}/#{repository}:#{image_tag}"
    Log.info(docker_build_cmd)
    
    unless system(docker_build_cmd)
      Log.warn("Failed to build image #{ecr_registry}/#{repository}:#{image_tag} - #{e}")
      raise "Failed to build image #{ecr_registry}/#{repository}:#{image_tag} - #{e}"
    end
    
    docker_images_cmd = "docker images --filter reference=#{ecr_registry}/#{repository}:#{image_tag}"
    Log.info(docker_images_cmd)
    system(docker_images_cmd)

    unless AwsHelper.ecr_repository_exists?(repository)
      AwsHelper.ecr_create_repository(
        repository_name: repository,
        image_tag_mutability: "IMMUTABLE",
        tags: Defaults.get_tags
      )
    end

    AwsHelper.ecr_set_repository_policy(
      repository_name: repository,
      policy_text: JSON.dump(Defaults.ecr_default_policy)
    )

    # TODO: required aws-sdk v2.11.234 to enable ECR scanning
    # AwsHelper.ecr_put_image_scanning_configuration(
    #   repository_name: repository,
    #   scan_on_push: true
    # )

    ecr_auth_token = AwsHelper.ecr_get_authorisation_token
    login_cmd = "docker login --username AWS --password #{ecr_auth_token} #{ecr_registry} "
    system(login_cmd)

    push_image_cmd = "docker push #{ecr_registry}/#{repository}:#{image_tag}"
    Log.info(push_image_cmd)
    system(push_image_cmd)

    begin
      rm_image_cmd = "docker rmi #{ecr_registry}/#{repository}:#{image_tag} --force"
      Log.info("Cleaning images post docker build task #{ecr_registry}/#{repository}:#{image_tag}")
      Log.info(rm_image_cmd)
      system(rm_image_cmd)
    rescue => e
      Log.warn("Failed to delete image #{ecr_registry}/#{repository}:#{image_tag} - #{e}")
    end

  rescue => e
    Log.error "Failed to execute Docker and ECR commands - #{e}"
  end

  def clean
    Log.info 'Cleaning up payload directory'
    begin
      FileUtils.rm_rf _env['PAYLOAD_BASE_DIR']
    rescue => e
      Log.error "Failed to execute task #{name} - #{e}"
      raise "Failed to execute task #{name} - #{e}"
    end
  end

  def all
    Defaults.set_pipeline_task('upload')
    task_exception = nil

    begin
      context_task.read

      # report to Splunk
      # call after context:read as we need env vars set
      begin
        stage_stats = StatHelper.start_pipeline_stage(
          context: Context,
          stage_name: 'upload'
        )
        Log.splunk_http(stage_stats)
      rescue => e
        Log.warn "Failed to report to Splunk - #{e} - #{e.backtrace}"
      end

      prepare
      validate
      package
      compliance
      checksum
      upload
      scan
      clean
      cdintegration
    rescue => e
      Log.error "upload has failed - #{e}"
      task_exception = e
      raise e
    ensure
      # report to Splunk
      # merging both exception if any, and validation_result from component validation task
      begin
          additional_hash = {}

          additional_hash.merge!(StatHelper.exceptions_stats(task_exception))
          additional_hash[:validation] = @validation_result

          stage_stats = StatHelper.finish_pipeline_stage(
            context: Context,
            stage_name: 'upload',
            additional_hash: additional_hash
          )

          Log.splunk_http(stage_stats)
      rescue => e
        Log.warn "Failed to report to Splunk - #{e} - #{e.backtrace}"
        end
    end
  end

  def context_task
    if @context_task.nil?
      @context_task = ContextTask.new
    end

    @context_task
  end

  def cdintegration
    # Invoke Bamboo CD if variable is set
    case
    when Defaults.invoke_bamboocd_enable.nil?
      Log.info "Bamboo plan variable \"invoke_bamboocd_enable\" is not set, Bamboo CD plan will not be invoked"
    when Defaults.invoke_bamboocd_enable.upcase == 'DISABLED'
      Log.info "Bamboo plan variable \"invoke_bamboocd_enable\" has been explicitly set to disabled, Bamboo CD plan will not be invoked"
    when Defaults.invoke_bamboocd_ase.upcase == 'PROD'
      Log.error "Bamboo plan variable \"invoke_bamboocd_ase\" has been set to #{Defaults.invoke_bamboocd_ase}, only non-prod environments supported"
    else
      Log.info "Bamboo plan variable \"invoke_bamboocd_enable\" is set, ASE is #{Defaults.invoke_bamboocd_ase}, Bamboo CD stage is #{Defaults.invoke_bamboocd_stage}, invoking Bamboo CD"
      begin
        bamboo_cd_api_baseurl = Defaults.bamboo_cd_api_baseurl
        master_cd_plan_key = Defaults.plan_key.sub(/CI[0-9]*$/, Defaults.invoke_bamboocd_ase)
        if Defaults.branch == 'master'
          Log.debug "Assuming master branch will not require plan key discovery, continuing to invoke Bamboo CD"
          cd_plan_key = master_cd_plan_key
        else
          # Listing branches of Bamboo CD plan and looping through to find relevant plan key
          plan_uri = "#{bamboo_cd_api_baseurl}plan/#{master_cd_plan_key}/branch.json"
          plan_res = Pipeline::Helpers::HTTP.get(url: plan_uri, ssl: true, user: Defaults.bamboo_pipeline_user, pass: Defaults.bamboo_pipeline_password)
          case plan_res.code
          when '200'
            plan = JSON.parse(plan_res.body)
            cd_plan_key = ''
            plan["branches"]["branch"].each do |branch|
              if branch["shortName"] == Defaults.branch.sub(/\//, '-')
                cd_plan_key = branch["key"]
              end
            end
          when nil
            Log.error "Failed to get a valid response from Bamboo CD using #{plan_uri}, unable to invoke plan"
            return
          else
            Log.error "Failed to locate plan using #{plan_uri}, Bamboo CD responded with status code #{plan_res.code}, unable to invoke plan"
            return
          end
        end
        # Invoking Bamboo CD
        queue_uri = "#{bamboo_cd_api_baseurl}queue/#{cd_plan_key}.json?stage=#{Defaults.invoke_bamboocd_stage}"
        Log.debug "Bamboo CD plan found for branch #{Defaults.branch}, plan key is #{cd_plan_key}"
        queue_res = Pipeline::Helpers::HTTP.post(url: queue_uri, ssl: true, user: Defaults.bamboo_pipeline_user, pass: Defaults.bamboo_pipeline_password)
        case queue_res.code
        when '200'
          Log.debug "Bamboo CD plan was successfully invoked using #{queue_uri}"
        when nil
          Log.error "Failed to get a valid response from Bamboo CD using #{queue_uri}, unable to invoke plan"
          return
        else
          Log.error "Failed to invoke plan using #{queue_uri}, Bamboo CD responded with status code #{queue_res.code}"
          return
        end
      rescue => e
        Log.error "Exception encountered while attempting to invoke Bamboo CD plan - #{e}"
        return
      end
    end
  end

  private

  def _is_enforced_validation(validation_mode)
    !validation_mode.nil? && validation_mode.downcase == 'enforce'
  end

  def _execute_custom_validators(data:, validation_mode:, validation_hash:)
    if !data.is_a?(ValidationData)
      raise "data should be of type ValidationData"
    end

    validation_service = ServiceContainer.instance.get_service(ValidationService)
    validation_result = validation_service.validate(data: data)

    _print_custom_validators_result(result: validation_result, validation_mode: validation_mode)
    _update_validation_hash(result: validation_result, validation_hash: validation_hash)
  end

  def _update_validation_hash(result:, validation_hash:)
    result.results.each do |validation_info|
      validation_hash[:messages] << validation_info.to_s
    end

    if !result.valid
      validation_hash[:is_valid] = result.valid
    end
  end

  def _print_custom_validators_result(result:, validation_mode:)
    enforced_validation = _is_enforced_validation(validation_mode)

    result.results.each do |validation_info|
      Log.output validation_info
    end

    if !result.valid && enforced_validation
      raise "One or more custom validation did not pass"
    end
  end
end
