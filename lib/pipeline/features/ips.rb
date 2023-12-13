require_relative '../feature'

module Pipeline
  module Features
    class IPS < Feature
      def initialize(component_name, specification)
        super
        @behaviour = specification.fetch('Behaviour', 'detective')
      end

      def name
        'ips'
      end

      def valid_stages
        %i[PreDeploy PostDeploy PostTeardown]
      end

      # @return (see Pipeline::Feature#feature_tags)
      def feature_tags
        [
          {
            key: "feature_#{name}",
            value: enabled? ? @behaviour : 'disabled'
          }
        ]
      end

      def activate(stage)
        super

        unless enabled?
          Log.info "IPS Feature is disabled. Skipping workflow"
          return
        end

        atora_release_arn = Defaults.atora_release_arn
        atora_payload = _generate_atora_payload(stage)

        Log.info "Triggering IPS #{stage} workflow: #{atora_release_arn}"

        _execute_workflow(atora_release_arn, atora_payload.to_json)
      rescue => error
        Log.error "Failed to execute IPS #{stage} workflow - #{error}"
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

      # Execute IPS workflow
      # @param function_name [String] Function name or ARN of the invoking function
      # @param payload [Hash] Payload to be submitted to the Trend workflow engine
      def _execute_workflow(function_name, payload)
        client = _lambda_client

        client.lambda_invoke(
          function_name: function_name,
          payload: payload,
          log_type: 'Tail'
        )

        Log.info "Successfully triggered IPS Workflow: #{function_name} with payload #{payload}"
      rescue => error
        raise "Failed to trigger IPS Workflow: #{function_name} with payload #{payload} - #{error}"
      end

      # Generate payload for IPS workflow invocation
      def _generate_atora_payload(stage)
        # Generate unique ID for IPS workflow invocation
        ips_workflow_name = SecureRandom.hex
        account_id = Context.environment.account_id

        action = {
          PreDeploy: 'pre-deploy',
          PostDeploy: 'post-deploy',
          PostTeardown: 'post-teardown'
        }.fetch(stage)

        return {
          action: action,
          tags: _component_tags,
          account_id: account_id,
          behaviour: @behaviour,
          execution_id: ips_workflow_name
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

        # if a custom invocation role is specified, use it as a provisioning role
        if Defaults.atora_invocation_role
          params[:provisioning_role] = Defaults.atora_invocation_role
          Log.info "Using provisioning role - #{Defaults.atora_invocation_role}"
        end

        return AwsHelperClass.new(**params)
      end
    end
  end
end
