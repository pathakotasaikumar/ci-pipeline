require 'util/json_tools'

class CloudFormationStateStorage
  def initialize()
  end

  def load(context_path)
    stack_name = _stack_name(context_path)

    begin
      Log.debug "Loading context for stack: #{stack_name}"
      template = AwsHelper.cfn_get_template(stack_name)
    rescue => e
      # QCP-2486
      # - return nil if stack does not exist
      # - reraise error and fail the build on any other errors

      if _is_valid_load_error?(e)
        Log.debug "Failed to load context, returning empty values - #{e}"
        return nil
      end

      Log.error "Failed to load context, reraising error - #{e}"
      raise
    end

    Log.debug "Loaded context for stack: #{stack_name}"

    return nil unless template.has_key? 'Resources'
    return nil unless template['Resources'].has_key? 'Storage'
    return nil unless template['Resources']['Storage'].has_key? 'Metadata'

    Log.debug "Stack isn't empty, returning 'Resources.Storage.Metadata' value"

    return JsonTools.get(template, 'Resources.Storage.Metadata', nil)
  end

  # Checks is an error is a valid to be reraised or suspessed during .load() call
  # 'stack noto exist' is alright but the rest of the errors must reraise
  # @return [Boolean]
  def _is_valid_load_error?(e)
    # something went very wrong
    if e.nil?
      return false
    end

    # if this is very first deployment, stack won't exists
    # pipeline will create it to save released builds and other info

    # error class: Aws::CloudFormation::Errors::ValidationError,
    # message: Stack with id ams03-p106-01-dev-QCP-2486-Release does not exist
    if e.to_s.downcase.include?("does not exist")
      return true
    end

    return false
  end

  def save(context_path, context)
    stack_name = _stack_name(context_path)
    Log.debug "Saving context for stack: #{stack_name}"

    stack_id = AwsHelper.cfn_stack_exists(stack_name)

    begin
      if context.nil?
        if stack_id.nil?
          Log.debug "Context is nil, but stack does not exist. Skipping"
        else
          Log.debug "Context is nil, deleting stack by id: #{stack_id}"
          AwsHelper.cfn_delete_stack(stack_id)
        end
      else
        template = _get_stack_template(context: context)

        if stack_id.nil?
          Log.debug "Context is not nil, stack does not exist - creating new stack: #{stack_name}"

          AwsHelper.cfn_create_stack(
            stack_name: stack_name,
            template: template,
            tags: Defaults.get_tags,
            wait_delay: 10,
          )
        else
          Log.debug "Context is not nil, stack exists - updating stack by name: #{stack_name}"

          AwsHelper.cfn_update_stack(
            stack_name: stack_name,
            template: template,
            wait_delay: 10,
            max_attempts: 30,
          )
        end
      end
    rescue => e
      error_message = "Failed to save the context - #{e}"
      Log.error error_message
      raise error_message
    ensure
      Log.debug "Completed saving context for stack: #{stack_name}"
    end
  end

  def _get_stack_template(context:)
    {
      'Resources' => {
        'Storage' => {
          'Type' => 'AWS::CloudFormation::WaitConditionHandle',
          'Metadata' => context
        }
      }
    }
  end

  def _stack_name(context_path)
    return context_path.join('-').gsub(/[^a-zA-Z0-9\-]/, '-')
  end
end
