require 'action'

class SetWeightRoutePolicy < Action
  # Initialised SetWeightRoutePolicy action object
  def initialize(component: nil, params: nil, stage: nil, step: nil)
    super

    @weight_value = params.fetch("Weight", nil)
    @record_set = params.fetch("RecordSet", nil)

    raise ArgumentError, "Weight and RecordSet are required parameters" if @weight_value.nil? || @record_set.nil?

    @status = params.fetch('Status', 'Healthy')
    @target = params.fetch('Target', '@deployed')
    @check_status = params.fetch('CheckStatus', true).to_s
    @stop_on_error = params.fetch('StopOnError', true).to_s

    @weight_value = @weight_value.to_i
    @build_number = case @target
                    when "@deployed"
                      Defaults.sections[:build]
                    when "@released"
                      Context.persist.released_build_number
                    else
                      raise "Unknown value for #{@target}, expected [@deployed/@released]"
                    end
  end

  # @return [Array] List of valid stages
  def valid_stages
    %w(
      PostDeploy
      PreRelease
      PostRelease
    )
  end

  # @return [Array] List of valid calling components
  def valid_components
    %w(
      aws/route53
    )
  end

  # @see Action#Invoke
  def invoke
    if @build_number.nil?
      Log.output "There are currently no released builds. "\
                 "Will not run SetWeightRoutePolicy command."
      return
    end

    stack_id = Context.component.stack_id(@component.component_name, @build_number)

    if stack_id.nil?
      msg = "Cannot find stack id for target #{@target} skipping action SetWeightRoutePolicy."
      if @stop_on_error == 'true'
        raise msg
      else
        Log.warn msg
        return
      end
    end

    begin
      # Retrieve the target build's component's stack template
      template = _template(
        stack_id: stack_id,
        record_set: @record_set,
        weight_value: @weight_value
      )

      # Wait for Health check to Unhealthy
      healthcheck = JsonTools.get(template, "Resources.#{@record_set}.Properties.HealthCheckId.Ref", nil)

      if healthcheck.nil?
        msg = "Cannot find stack healthcheck id for target #{@target}."
        if @stop_on_error == 'true'
          raise "#{msg}. Failing SetWeightRoutePolicy action"
        else
          Log.warn "#{msg}. Skipping SetWeightRoutePolicy action"
          return
        end
      end

      healthcheckid = Context.component.variable(
        @component.component_name, "#{healthcheck}HealthCheckId", nil, @build_number
      )

      if @check_status == 'true'
        AwsHelper._route53_check_health_status(
          healthcheckid: healthcheckid,
          status: @status
        )
      end

      unless template.nil?
        AwsHelper.cfn_update_stack(stack_name: stack_id, template: template)
      end

      Log.output "SUCCESS: Updated the Route53 RecordSet #{@record_set.inspect} and with value #{@weight_value}"
    rescue => error
      raise "ERROR: Failed to update the Route53 RecordSet #{@record_set.inspect} - #{error}" if @stop_on_error == 'true'

      Log.warn "ERROR: Failed to update the Route53 RecordSet #{@record_set.inspect} - #{error} - continuing execution"
    end
  end

  private

  # retrieve the cloudformation
  # @param stack_id [String] stack id
  # @param record_set [String] Record set value
  # @param weight_value [String] weight value
  def _template(stack_id:, record_set:, weight_value:)
    template = AwsHelper.cfn_get_template(stack_id)

    resource = JsonTools.get(template, "Resources.#{record_set}", nil)
    raise "Recordset #{record_set.inspect} does not exist in the target build" if resource.nil?

    current_weight_value = JsonTools.get(resource, "Properties.Weight", nil)
    raise "Recordset #{record_set.inspect} does not have value for Weighted Alias" if current_weight_value.nil?

    # Update the recordset value
    resource["Properties"]["Weight"] = weight_value

    template
  end
end
