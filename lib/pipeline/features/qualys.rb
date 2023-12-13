# class for Qualys related operations
require 'securerandom'
require_relative '../feature'

module Pipeline
  module Features
    class Qualys < Feature
      def initialize(component_name, specification)
        super
        @recipients = specification.fetch('Recipients')
      end

      # Return name the feature name as a string
      # @return [String] name
      def name
        'qualys'
      end

      def valid_stages
        %i[PostDeploy]
      end

      # Activate Qualys scan feature, by invoking Qualys scan
      def activate(stage)
        super

        unless enabled?
          Log.info "Qualys Feature is disabled/ Skipping deploy time scan"
          return
        end

        aqos_release_arn = Defaults.aqos_release_arn
        aqos_payload = _generate_scan_payload

        Log.info  "Triggering Qualys Workflow: #{aqos_release_arn}"
        Log.debug "  - recipients   : #{aqos_payload['recipients']}"
        Log.debug "  - execution_id : #{aqos_payload['execution_id']}"
        Log.debug "  - account_id   : #{aqos_payload['account_id']}"
        Log.debug "  - tags         : #{aqos_payload['tags']}"

        _execute_scan(aqos_release_arn, aqos_payload.to_json)
      rescue => error
        Log.error "Failed to execute Qualys scan request - #{error}"
      end

      # @return (see Pipeline::Feature#feature_tags)
      def feature_tags
        feature_status = enabled? ? 'enabled' : 'disabled'
        [
          {
            key: "feature_#{name}",
            value: feature_status
          }
        ]
      end

      # @return (see Pipeline::Feature#feature_properties)
      def feature_properties
        { 'status' => enabled? ? 'enabled' : 'disabled' }
      end

      private

      # Returns component tags
      # @return [Hash] Component tags as key / values
      def _component_tags
        tags = {}
        Defaults.get_tags(@component_name).map do |tag|
          tags[tag[:key]] = tag[:value]
        end
        return tags
      end

      # Execute Qualys authenticated scan workflow
      # @param function_name [String] Function name or ARN of the invoking function
      # @param payload [Hash] Payload to be submitted to the Qualys workflow engine
      def _execute_scan(function_name, payload)
        client = _lambda_client
        client.lambda_invoke(
          function_name: function_name,
          payload: payload,
          log_type: 'Tail'
        )
        Log.info "Successfully triggered Qualys Workflow: #{function_name} with payload #{payload}"
      rescue => error
        raise "Failed to trigger Qualys Workflow: #{function_name} with payload #{payload} - #{error}"
      end

      # Generate payload for AQOS scan
      def _generate_scan_payload
        # Generate unique ID for qualys scan workflow
        qualys_workflow_name = SecureRandom.hex
        account_id = Context.environment.account_id

        return {
          tags: _component_tags,
          account_id: account_id,
          recipients: @recipients,
          execution_id: qualys_workflow_name
        }
      end

      # Create an AwsHelper with Control Role credentials
      # Note: Ensures invocation takes place in the pipeline control account
      # @return [Object] AwsHelper object used as a wrapper for AWS APIs
      def _lambda_client
        # Use Control Provisioning Role
        return AwsHelperClass.new(
          proxy: Defaults.proxy,
          region: Defaults.region,
          control_role: Defaults.control_role
        )
      end
    end
  end
end
