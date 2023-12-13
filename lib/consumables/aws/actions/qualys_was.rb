# Class implements action responsible for invoking Qualys WAS workflow

require 'action'
require 'securerandom'
class QualysWAS < Action
  def initialize(component: component_name, params: nil, stage: nil, step: nil)
    super
    raise ArgumentError, "ScanConf parameter must be specified" if params['ScanConf'].nil? || params['ScanConf'].empty?
    raise ArgumentError, "qualys_was parameter must be specified in ScanConf" if params['ScanConf']['qualys_was'].nil? || params['ScanConf']['qualys_was'].empty?

    @was_payload = params['ScanConf']['qualys_was']
    @stop_on_error = params.fetch('StopOnError', 'false')
  end

  # @return [Array] List of valid stages
  def valid_stages
    %w(
      PostDeploy
      PostRelease
    )
  end

  # @return [Array] List of valid calling components
  def valid_components
    [:all]
  end

  # Function to trigger Qualys WAS workflow
  def _execute_scan(function_name, payload)
    client = _aws_helper_client
    client.lambda_invoke(
      function_name: function_name,
      payload: payload,
      log_type: 'Tail'
    )
    Log.info "Successfully triggered Qualys WAS Workflow: #{function_name} with payload #{payload}"
  rescue => error
    raise "Failed to trigger Qualys WAS Workflow: #{function_name} with payload #{payload} - #{error}"
  end

  # Returns component tags
  # @return [Hash] Component tags as key / values
  def _component_tags
    tags = {}
    Defaults.get_tags(@component_name).map do |tag|
      tags[tag[:key]] = tag[:value]
    end
    return tags
  end

  # Generate payload for Qualys WAS
  def _generate_was_scan_payload
    # Generate unique ID for qualys WAS scan workflow
    qualys_workflow_name = SecureRandom.hex
    account_id = Context.environment.account_id

    Log.debug "Qualsy WAS payload from ScanConf: " + Context.component.replace_variables(@was_payload).to_json

    return {
      tags: _component_tags,
      account_id: account_id,
      execution_id: qualys_workflow_name,
      qualys_was: Context.component.replace_variables(@was_payload)
    }
  end

  # Create an AwsHelper with Control Role credentials
  # Note: Ensures invocation takes place in the pipeline control account
  # @return [Object] AwsHelper object used as a wrapper for AWS APIs
  def _aws_helper_client
    # Use Platform Provisioning Role
    return AwsHelperClass.new(
      proxy: Defaults.proxy,
      region: Defaults.region,
      control_role: Defaults.control_role
    )
  end

  # Invoking Qualys WAS
  def invoke
    aqos_release_arn = Defaults.aqos_release_arn
    aqos_payload = _generate_was_scan_payload

    Log.info  "Triggering Qualys WAS Workflow: #{aqos_release_arn}"
    Log.debug "  - execution_id : #{aqos_payload['execution_id']}"
    Log.debug "  - account_id   : #{aqos_payload['account_id']}"
    Log.debug "  - tags         : #{aqos_payload['tags']}"

    _execute_scan(aqos_release_arn, aqos_payload.to_json)
  rescue => error
    msg = "Failed to execute Qualys WAS scan request - #{error}"
    if @stop_on_error == 'true'
      raise "#{msg}. Failing Qualys WAS action"
    else
      Log.warn "#{msg}. Skipping Qualys WAS action"
      return
    end
  end
end
