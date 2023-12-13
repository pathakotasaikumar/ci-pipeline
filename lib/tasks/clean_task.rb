require 'component'
require 'runner'
require_relative 'base_task'

class CleanTask < BaseTask
  @context_task

  def name
    "clean"
  end

  def all
    logs
    context
    artefacts
  end

  def logs
    context_task.read

    return unless _env['local_dev']

    bucket_name = Context.s3.artefact_bucket_name
    sections = Defaults.sections

    # Delete local logs
    FileUtils.rm_rf(File.join(File.expand_path("..", Dir.pwd), "logs"))

    # Delete remote logs
    path = "logs/#{sections[:ams]}/#{sections[:qda]}/#{sections[:as]}/#{sections[:ase]}/#{sections[:branch]}"
    AwsHelper.s3_delete_objects(bucket_name, path)
  end

  def context
    context_task.read

    return unless _env['local_dev']

    bucket_name = Context.s3.pipeline_bucket_name
    sections = Defaults.sections

    # Clean up branch context
    path = "#{sections[:ams]}/#{sections[:qda]}/#{sections[:as]}/#{sections[:ase]}/#{sections[:branch]}"
    AwsHelper.s3_delete_objects(bucket_name, path)

    # Clean up env context
    path = "#{sections[:ams]}/#{sections[:qda]}/#{sections[:as]}/env-#{sections[:env]}"
    AwsHelper.s3_delete_objects(bucket_name, path)
  end

  def artefacts
    context_task.read

    return unless _env['local_dev']

    bucket_name = Context.s3.artefact_bucket_name
    sections = Defaults.sections

    # Clean up CI artefacts
    path = "ci/#{sections[:ams]}/#{sections[:qda]}/#{sections[:as]}/#{sections[:branch]}"
    AwsHelper.s3_delete_objects(bucket_name, path)

    # Clean up CD artefacts
    path = "cd/#{sections[:ams]}/#{sections[:qda]}/#{sections[:as]}/#{sections[:ase]}/#{sections[:branch]}"
    AwsHelper.s3_delete_objects(bucket_name, path)
  end

  def context_task
    if @context_task.nil?
      @context_task = ContextTask.new
    end

    @context_task
  end

  def cloudformation
    context_task.read
    return unless _env['local_dev']

    sections = Defaults.sections

    stacks = AwsHelper.cfn_describe_all_stacks
    stacks = stacks.select { |stack| is_related_stack?(stack, sections) }
    Log.info "Stacks matching current build environment - #{stacks.length}"

    stacks.each_with_index do |stack, i|
      Log.info " - #{stack.stack_name}"
    end
    if !stacks.empty?
      STDOUT.puts "Are you sure you want to terminate these stacks? (y/n)"
      input = STDIN.gets.strip
      if input == 'y'
        stacks.each_with_index do |stack, i|
          AwsHelper.cfn_delete_stack(stack.stack_name, wait_for_completion = false)
        end
      end
    end
  end

  def is_related_stack?(stack, sections)
    return (
      stack.tags.any? { |t| t['key'] == 'EnterpriseAppID' && t['value'] == sections[:qda].upcase } &&
      stack.tags.any? { |t| t['key'] == 'ApplicationServiceID' && t['value'] == sections[:as].upcase } &&
      stack.tags.any? { |t| t['key'] == 'AMSID' && t['value'] == sections[:ams].upcase } &&
      stack.tags.any? { |t| t['key'] == 'Environment' && t['value'] == sections[:ase].upcase } &&
      stack.tags.any? { |t| t['key'] == 'AsbpType' && t['value'] == sections[:asbp_type].upcase } &&
      !stack.stack_name.end_with?("kms")
    )
  end
end
