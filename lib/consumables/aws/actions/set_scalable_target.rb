require "action"
require "context_class"

# Class instantiates action for controlling ApplicationAutoScaling:ScalableTarget
# @attr target [String] targeted resource
# @attr min_capacity [Int,String] minimum capacity for target application autoscaling
# @attr max_capacity [Int,String] maximum capacity for target application autoscaling

class SetScalableTarget < Action
  # Initialised SetScalableTarget action object
  def initialize(component: nil, params: nil, stage: nil, step: nil)
    super

    @min_capacity = params["MinCapacity"]
    @max_capacity = params["MaxCapacity"]
    @target = params["Target"] || "@deployed"
    @timeout = (params["Timeout"] || 900)
    @stop_on_error = (params.has_key? "StopOnError") ? params["StopOnError"] : true

    raise ArgumentError, "MinCapacity and MaxCapacity must be specified" if @min_capacity.nil? || @max_capacity.nil?
    raise ArgumentError, "Invalid timeout #{@timeout}, must be between 0 and 3600" unless @timeout.to_i.between?(0, 3600)
    raise ArgumentError, "Invalid target #{@target} for action SetScalableTarget" unless %w(@deployed @released).include? @target

    @min_capacity = @min_capacity.to_i
    @max_capacity = @max_capacity.to_i
    @timeout = @timeout.to_i

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
      aws/ecs-task
    )
  end

  def invoke
    if @build_number.nil?
      Log.output "There are currently no released builds. "\
                 "Will not run SetScalableTarget command."
      return
    end

    # Retrieve ASG name
    scalable_target_name = @component.scalable_target.keys.first      
    component_component_name = @component.component_name

    scalable_target_name_id = Context.component.variable(
      @component.component_name, "#{scalable_target_name}Name", nil, @build_number
    )

    stack_id = Context.component.stack_id(
      @component.component_name,
      @build_number
    )

    if [scalable_target_name_id, stack_id].any?(&:nil?)
      Log.output "Cannot find scalable target or stack id for target #{@target}" \
                 " (#{scalable_target_name_id}), skipping action SetScalableTarget."
      return
    end

    begin
      # Retrieve the target build's component's stack template

      template = build_template(
        stack_id: stack_id,
        scalable_target_name: scalable_target_name
      )

      Log.info "Performing stack update while #{print_scalable_target}"
      AwsHelper.cfn_update_stack(stack_name: stack_id, template: template)

      resource = JsonTools.get(template, "Resources.#{scalable_target_name}", nil)
      raise "Scalable target #{scalable_target_name.inspect} does not exist in target build #{@target}" if resource.nil?      
      service_namespace = resource["Properties"]["ServiceNamespace"]
      
      # Wait for ASG to reach target capacity
      Log.info "Waiting for component #{@component.component_name} #{@target} "\
               "Scalable target to reach target capacity (min #{@min_capacity}, max #{@max_capacity})"
      
      
      stack_status = AwsHelper._cfn_get_stack_status(
        stack_name: stack_id         
      )
      
      AwsHelper.scalable_target_wait_for_capacity(
        service_namespace: service_namespace, 
        scalable_target_id: scalable_target_name_id.split('|')[0],
        min_capacity: @min_capacity,
        max_capacity: @max_capacity,
        delay: 30,
        max_attempts: (@timeout / 30.0).ceil
      )

      # Process any features which may be applicable on change in desired capacity
      _process_features

      Log.output "SUCCESS: #{print_scalable_target}"
    rescue => error
      raise "ERROR: #{print_scalable_target} - #{error}" if @stop_on_error

      Log.warn "ERROR: #{print_scalable_target} - #{error} - continuing execution"
    ensure
      # Copy all the produced log files to a local log directory
      wait_condition = JsonTools.get(
        template, "Resources.#{scalable_target_name}.Metadata.WAIT_CONDITION", nil
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
    scalable_target_name: nil
  )

    template = AwsHelper.cfn_get_template(stack_id)

    resource = JsonTools.get(template, "Resources.#{scalable_target_name}", nil)
    raise "Scalable target #{scalable_target_name.inspect} does not exist in target build #{@target}" if resource.nil?
  
    resource["Properties"]["MinCapacity"] = @min_capacity
    resource["Properties"]["MaxCapacity"] = @max_capacity
   
    template
  end

  def print_scalable_target
    "Executing SetScalableTarget (min #{@min_capacity}, max #{@max_capacity}) on component #{@component.component_name} #{@target}"
  end

  def capacity_zero?
    @min_capacity <= 0 && @max_capacity <= 0
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
