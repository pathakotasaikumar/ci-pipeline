require 'net/http'
require 'openssl'
require 'json'
require 'util/archive'

module Pipeline
  module Helpers
    # Helper module for handling Veracode requests
    class Veracode
      def initialize(
        branch:,
        scan_dir:,
        config:
      )

        @branch = branch
        @scan_dir = scan_dir

        @avos_release_arn = Defaults.avos_release_arn
        @app_name = Defaults.avos_app_name
        @bucket_name = Defaults.avos_bucket_name
        @artefact_prefix = Defaults.avos_artefact_prefix

        @crit = config.fetch('crit')
        @recipients = config.fetch('recipients')
        @promote_branch = config.fetch('promote_branch')
        @scan_branch = config.fetch('scan_branch', [])
        @artefact_filename = Defaults.avos_artefact_filename
      end

      # Run Veracode scan only if:
      #   scan_branch property is not set
      #   includes the current branch
      # @return [Bool] Check if Veracode scan should be executed or not for the current branch
      def enabled?
        @scan_branch.blank? || @scan_branch.include?(@branch)
      end

      # Package scan artefacts in the Scan Directory for upload
      def package
        artefact_scan_filename = File.join(@scan_dir, @artefact_filename)
        Util::Archive.tgz!(@scan_dir, artefact_scan_filename)
        Log.info "Created a new Veracode scan artefact: #{artefact_scan_filename}"
      end

      # Uploads artefacts to a staging area to be picked up by the Veracode workflow
      def upload
        # Upload scan.tar.gz
        veracode_artefact = File.join(@scan_dir, @artefact_filename)

        # Upload code artefact for veracode
        veracode_artefact_s3_path = "#{@artefact_prefix}/#{@artefact_filename}"

        AwsHelper.s3_upload_file(
          @bucket_name,
          veracode_artefact_s3_path,
          veracode_artefact
        )
        Log.info "Uploaded veracode artefact file: #{veracode_artefact_s3_path}"
      end

      # Compile payload and trigger execution of AVOS workflow
      def run
        avos_payload = _generate_avos_payload
        _execute_scan(@avos_release_arn, avos_payload.to_json)
      end

      # @param scan_file [String] Absolute path to the Veracode scan.yaml configuration file
      # @param type [String] Tybe of the static analysis workflow to run (default: veracode)
      def self.load_config(scan_file, type = 'veracode')
        config = YAML.load_file(scan_file).fetch(type)
        _validate_config(config)
        return config
      rescue => e
        Log.error "Unable to load Veracode configuration file: #{scan_file} - #{e}"
        return {}
      end

      private

      # Validate scan.yaml configuration file
      # @param config [Hash] Properties for veracode scan
      def self._validate_config(config)
        raise ArgumentError('Missing Argument - crit') if config.fetch('crit', nil).blank?
        raise ArgumentError('Missing Argument - recipients') if config.fetch('recipients', []).blank?

        Log.warn "Missing Argument - 'promote_branch'. Skipping Policy Scan" if config.fetch('promote_branch', nil).blank?
        Log.warn "Missing Argument - 'scan_branch'. Running for all branches" if config.fetch('scan_branch', nil).blank?
      end

      # Execute Veracode scan
      # @param function_name [String] Function name or ARN of the invoking function
      # @param payload [Hash] Payload to be submitted to the Veracode workflow engine
      def _execute_scan(function_name, payload)
        _lambda_client.lambda_invoke(
          function_name: function_name,
          payload: payload,
          log_type: 'Tail'
        )
        Log.info "Successfully triggered Veracode Workflow: #{function_name} with payload #{payload}"
      rescue => error
        raise "Failed to trigger Veracode Workflow: #{function_name} with payload #{payload} - #{error}"
      end

      # Generate AVOS payload based on the object instance variables
      # @return [Hash] AVOS payload used for workflow trigger
      def _generate_avos_payload
        veracode_execution_id = SecureRandom.hex

        return {
          app_name: @app_name,
          artefact: @artefact_filename,
          branch: @branch,
          bucket: @bucket_name,
          crit: @crit,
          execution_id: veracode_execution_id,
          path: @artefact_prefix,
          promote_branch: @promote_branch,
          recipients: @recipients,
          tag: @app_name
        }
      end

      # Create an AwsHelper with Control Role credentials
      # Note: Ensures invocation takes place in the pipeline control account
      # @return [Object] AwsHelper object used as a wrapper for AWS APIs
      def _lambda_client
        params = {
          proxy: Defaults.proxy,
          region: Defaults.region,
          control_role: Defaults.control_role
        }

        # Use custom invocation role if supplied as a parameter/variable
        invocation_role = Defaults.avos_invocation_role
        params[:provisioning_role] = invocation_role unless invocation_role.nil?

        return AwsHelperClass.new(**params)
      end
    end
  end
end
