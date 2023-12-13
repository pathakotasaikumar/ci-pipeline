class KmsContext
  def initialize(state_storage, sections)
    @state_storage = state_storage
    @secrets_context = nil

    @secrets_context_path = [sections[:ams], sections[:qda], sections[:as], 'env-' + sections[:env], 'Kms']
  end

  def set_secrets_details(stack_id, key_arn)
    @secrets_context = {
      'StackId' => stack_id,
      'KeyArn' => key_arn,
    }
    @state_storage.save(@secrets_context_path, @secrets_context)

    Context.component.set_variables("pipeline", {
      "KmsKeyArn" => key_arn,
    })
  end

  # ARN of the KMS key used by the application for encryption operations
  # These keys are created by the onboarding or by the pipeline on the fly
  # For example: ams03-p106-01-nonp, ams03-p109-03-nonp and so on
  # @return [String] ARN of the key
  def secrets_key_arn
    return _secrets_context['KeyArn']
  end

  def _secrets_context
    if @secrets_context.nil?
      Log.info "Loading secrets KMS context"
      @secrets_context = @state_storage.load(@secrets_context_path) || {}

      if !@secrets_context["KeyArn"].nil?
        Context.component.set_variables("pipeline", {
          "KmsKeyArn" => @secrets_context["KeyArn"],
        })
      end
    end
    Log.info "Secrets Context: #{@secrets_context}"
    return @secrets_context
  end

  def flush
    # Do Nothing
  end
end
