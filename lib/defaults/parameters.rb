module Defaults
  module Parameters
    extend self

    # stores current pipeline task
    # - upload (CI)
    # - deploy, release, teardown (CD)
    @@pipeline_task_name = nil

    # stores ARGV array
    @@argv_value = nil

    # Parameters
    # Note: values below will be sourced via SSM parameters as first preference

    # Returns the default
    def pipeline_parameter_prefix
      ENV.fetch('pipeline_parameter_prefix', '/pipeline')
    end

    def ad_join_domain
      Context.environment.variable('ad_join_domain', nil)
    end

    def ad_join_user
      Context.environment.variable('ad_join_user', nil)
    end

    def ad_join_password
      Context.environment.variable('ad_join_password', nil)
    end

    def asir_dynamodb_table_name
      Context.environment.variable('asir_dynamodb_table_name', nil)
    end

    def pipeline_build_metadata_dynamodb_table_name
      Context.environment.variable('pipeline_build_metadata_table_name')
    end

    # AWS Proxy
    def aws_proxy
      Context.environment.variable('aws_proxy', nil)
    end

    def legacy_bucket_name
      Context.environment.variable('legacy_bucket_name', 'pipeline-artefact-store')
    end

    def secrets_bucket_name
      Context.environment.variable('secrets_bucket_name', 'qcp-secret-management-bucket')
    end

    def secrets_file_location_path
      Context.environment.variable('secrets_file_location_path', 'platform-secrets-storage/secrets.json')
    end

    def artefact_bucket_name
      Context.environment.variable('artefact_bucket_name', 'qcp-pipeline-artefacts')
    end

    def lambda_artefact_bucket_name
      Context.environment.variable('lambda_artefact_bucket_name', 'qcp-pipeline-lambda-artefacts')
    end

    def soe_ami_ids
      Context.environment.variable('soe_ami_ids', nil)
    end

    def soe_ami_id(name)
      soe_ami_ids = Defaults.soe_ami_ids

      if soe_ami_ids.nil? || soe_ami_ids.empty?
        raise "Cannot find SOE AMI id - no SOE AMI ids have been defined, set variable soe_ami_ids"
      end

      past_ids = []
      ami_id = nil

      key = name.start_with?('@') ? name : "@#{name}"
      while key.start_with? '@'
        # Prevent circular lookups
        circular_lookup = past_ids.include? key
        past_ids << key
        raise "Cannot find SOE AMI id for alias #{name.inspect} - circular lookup #{past_ids.inspect}" if circular_lookup

        # Lookup the key
        key = key.downcase[1..-1]
        raise "Cannot find SOE AMI id for alias #{name.inspect} - #{key.inspect} doesn't exist" unless soe_ami_ids.key? key

        key = soe_ami_ids[key]
      end

      # if key looks like a DNS record, do a lookup for AMI ID
      record = key.match(/^[\w-]+\.[\w-]+\.[\w-]+\.[\w-]+\.[\w-]+(\.nonp)?$/) ? key + ".#{Defaults.dns_zone}" : key

      if record =~ /^[\w-]+\.[\w-]+\.[\w-]+\.[\w-]+\.[\w-]+(\.nonp)?\.qcpaws\.qantas\.com\.au$/
        Log.debug "Looking up AMI for #{record}"
        ami_id = Defaults.image_by_dns record
      else
        ami_id = key
      end

      return ami_id unless ami_id.nil?
    end

    def pipeline_validation_mode
      Context.environment.variable('validation_mode', 'enforce')
    end

    def pipeline_use_custom_validation?
      custom_validation_flag = Context.environment.variable('pipeline_custom_validation', nil)

      !custom_validation_flag.nil? && !custom_validation_flag.to_s.empty?
    end

    # sets ARVG array
    # it can later be used via Defaults.argv method
    def set_argv(argv)
      @@argv_value = argv
    end

    # returns ARVG array
    # @return (Array)
    def argv
      @@argv_value
    end

    # parses ARVG array set early via Defaults.set_argv
    # pipeline uses this array to set pre-initialized state from the CLI
    def parse_argv
      Log.debug "Parsing ARGV values"

      pipeline_task_names = [
        # upload is called under CI
        # upload:validate can be called locally to validate pipeline's components
        'upload', 'upload:validate',
        # CD tasks
        'deploy', 'release', 'teardown'
      ]

      known_task      = false
      known_task_name = ''

      pipeline_task_names.each do |task_name|
        if argv.include?(task_name)
          Log.debug "Detected pipeline task: #{task_name}"
          set_pipeline_task(task_name)

          known_task      = true
          known_task_name = task_name

          break
        end
      end

      if !known_task
        Log.error [
          "Cannot find known pipeline task, build will continue but deployment might fail.",
          "Use one of the following values: #{pipeline_task_names.join(', ')}"
        ].join(" ")
      else
        Log.debug "Running pipeline task: #{known_task_name}"
      end
    end

    # sets current pipeline task
    # it can later be used via Defaults.pipeline_task method
    def set_pipeline_task(task_name)
      @@pipeline_task_name = task_name
    end

    # returns current pipeline task - upload, deploy, release or teardown
    # @return (String)
    def pipeline_task
      if @@pipeline_task_name.to_s.empty?
        error_message = 'pipeline_task variable is not set, call Defaults.set_pipeline_task() early'
        Log.error error_message
        raise error_message
      end

      @@pipeline_task_name
    end

    # returns true if current task is CI (upload)
    # @return (Boolean)
    def is_ci_pipeline_task?
      ['upload'].include? pipeline_task
    end

    # returns true if current task is CD (deploy, release, teardown)
    # @return (Boolean)
    def is_cd_pipeline_task?
      [
        'deploy',
        'release',
        'teardown'
      ].include? pipeline_task
    end

    def permission_boundary_policy
      Context.environment.variable('permission_boundary_policy', 'PermissionBoundaryPolicy')
    end
  end
end
