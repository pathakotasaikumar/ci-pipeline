require "action"
require "context_class"

# Class instantiates action for controlling autoscaling capacity
# @attr target [String] targeted resource
# @attr [Int,String] desired_capacity desired number of instances for target autoscaling group
# @attr min_size [Int,String] minimum number of instances for target autoscaling group
# @attr max_size [Int,String] maximum number of instances for target autoscaling group

class SetDesiredCapacity < Action
  # Initialised SetDesiredCapacity action object
  def initialize(component: nil, params: nil, stage: nil, step: nil)
    super

    @min_size = params["MinSize"]
    @max_size = params["MaxSize"]
    @desired_capacity = params["DesiredCapacity"]
    @target = params["Target"] || "@deployed"
    @timeout = (params["Timeout"] || 300)
    @stop_on_error = (params.has_key? "StopOnError") ? params["StopOnError"] : true

    raise ArgumentError, "MinSize and MaxSize must be specified" if @min_size.nil? || @max_size.nil?
    raise ArgumentError, "Invalid timeout #{@timeout}, must be between 0 and 3600" unless @timeout.to_i.between?(0, 3600)
    raise ArgumentError, "Invalid target #{@target} for action SetDesiredCapacity" unless %w(@deployed @released).include? @target

    @min_size = @min_size.to_i
    @max_size = @max_size.to_i
    @desired_capacity = @desired_capacity.to_i unless @desired_capacity.nil?
    @timeout = @timeout.to_i

    @build_number = case @target
                    when "@deployed"
                      Defaults.sections[:build]
                    when "@released"
                      Context.persist.released_build_number
                    else
                      raise "Unknown value for #{@target}, expected [@deployed/@released]"
                    end

    if component.type == "aws/autoheal"
      if [@desired_capacity, @min_size, @max_size].any? { |p| !([nil, 0, 1].include? p) }
        raise "aws/autoheal component only supports '0' and '1' for MinSize, MaxSize, and DesiredCapacity properties"
      end
    end
  end

  # @return [Array] List of valid stages
  def valid_stages
    %w(
      PreDeploy
      PostDeploy
      PreRelease
      PostRelease
      PreTeardown
      PostTeardown
    )
  end

  # @return [Array] List of valid calling components
  def valid_components
    %w(
      aws/autoscale
      aws/autoheal
    )
  end

  def invoke
    if @build_number.nil?
      Log.output "There are currently no released builds. "\
                 "Will not run SetDesiredCapacity command."
      return
    end

    # Retrieve ASG name
    asg_resource_name = @component.autoscaling_group.keys.first
    autoscaling_group_name = Context.component.variable(
      @component.component_name, "#{asg_resource_name}Name", nil, @build_number
    )

    stack_id = Context.component.stack_id(
      @component.component_name,
      @build_number
    )

    if [autoscaling_group_name, stack_id].any?(&:nil?)
      Log.output "Cannot find autoscaling group or stack id for target #{@target}" \
                 " (#{asg_resource_name}), skipping action SetDesiredCapacity."
      return
    end

    begin
      # Retrieve the target build's component's stack template

      template = build_template(
        stack_id: stack_id,
        asg_resource_name: asg_resource_name
      )

      if template.nil?
        Log.info "Performing API call  while #{print_desired_capacity}"
        AwsHelper.autoscaling_set_capacity(
          autoscaling_group_name: autoscaling_group_name,
          min_size: @min_size,
          desired_capacity: @desired_capacity,
          max_size: @max_size
        )
      else
        Log.info "Performing stack update while #{print_desired_capacity}"
        AwsHelper.cfn_update_stack(stack_name: stack_id, template: template)
      end

      # Wait for ASG to reach target capacity
      Log.info "Waiting for component #{@component.component_name} #{@target} "\
               "ASG to reach target capacity (min #{@min_size}, max #{@max_size})"
      AwsHelper.autoscaling_wait_for_capacity(
        autoscaling_group_name: autoscaling_group_name,
        min_size: @min_size,
        max_size: @max_size,
        delay: 30,
        max_attempts: (@timeout / 30.0).ceil
      )

      # Process any features which may be applicable on change in desired capacity
      _process_features

      Log.output "SUCCESS: #{print_desired_capacity}"
    rescue => error
      raise "ERROR: #{print_desired_capacity} - #{error}" if @stop_on_error

      Log.warn "ERROR: #{print_desired_capacity} - #{error} - continuing execution"
    ensure
      # Copy all the produced log files to a local log directory
      wait_condition = JsonTools.get(
        template, "Resources.#{asg_resource_name}.Metadata.WAIT_CONDITION", nil
      )
      unless wait_condition.nil?
        AwsHelper.s3_download_objects(
          bucket: Context.s3.artefact_bucket_name,
          prefix: Defaults.log_upload_path(
            component_name: @component.component_name,
            type: "deploy/#{wait_condition}"
          ),
          local_path: "#{Defaults.logs_dir}/#{@component.component_name}/#{stage}",
          validate: false
        )
      end
    end
  end

  private

  def build_template(
    stack_id: nil,
    asg_resource_name: nil
  )

    template = AwsHelper.cfn_get_template(stack_id)

    resource = JsonTools.get(template, "Resources.#{asg_resource_name}", nil)
    raise "ASG #{asg_resource_name.inspect} does not exist in target build #{@target}" if resource.nil?

    # Check if we are updating resource with a wait condition
    previous_wait_condition_name = JsonTools.get(resource, "Metadata.WAIT_CONDITION", nil)
    return nil if previous_wait_condition_name.nil?

    # Wait for app signals if target app is currently not running at all
    if resource["Properties"]["MaxSize"].to_i.zero?
      Log.debug "Setting #{asg_resource_name.inspect} to wait for #{@desired_capacity || @min_size} signals"

      # Replace wait condition resource with a new one
      template["Resources"].delete(previous_wait_condition_name)
      wait_condition_name = "Wait#{Time.now.strftime('%s')}"
      template["Resources"][wait_condition_name] = {
        "Type" => "AWS::CloudFormation::WaitCondition",
        "Properties" => {},
        "CreationPolicy" => {
          "ResourceSignal" => {
            "Count" => @desired_capacity || @min_size,
            "Timeout" => JsonTools.get(
              resource, "CreationPolicy.ResourceSignal.Timeout", "PT45M"
            )
          }
        }
      }

      resource["Metadata"]["WAIT_CONDITION"] = wait_condition_name
    end

    resource["Properties"]["MinSize"] = @min_size
    resource["Properties"]["MaxSize"] = @max_size
    resource["Properties"].delete("DesiredCapacity")
    resource["Properties"]["DesiredCapacity"] = @desired_capacity unless @desired_capacity.nil?

    template
  end

  def print_desired_capacity
    "Executing SetDesiredCapacity (min #{@min_size}, "\
    "desired #{@desired_capacity || 'X'}, max #{@max_size}) on "\
    "component #{@component.component_name} #{@target} ASG, "
  end

  def capacity_zero?
    @min_size <= 0 && @max_size <= 0
  end

  # Process applicable features to this action
  def _process_features
    component.pipeline_features.each do |feature|
      feature_name = feature.name.downcase
      begin
        case feature_name
        when 'qualys', 'ips'
          feature.activate(:PostDeploy) unless capacity_zero?
        end
      rescue => error
        Log.error "Failed to process post_deploy task for feature #{feature_name} - #{error}"
      end
    end
  end
end
