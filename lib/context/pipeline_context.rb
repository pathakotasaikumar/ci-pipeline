class PipelineContext
  def initialize(state_storage, sections)
    @context = ContextStorage.new(
      name: 'Pipeline',
      state_storage: state_storage,
      path: [sections[:ams], sections[:qda], sections[:as], sections[:ase], sections[:branch], sections[:build], "Pipeline"],
      sync: true
    )
  end

  def variable(variable_name, default = :undef)
    return @context.variable(variable_name, default)
  end

  def variables
    return @context.variables
  end

  def set_variables(variables)
    return @context.set_variables(variables)
  end

  def state
    return @context.variable('State', 'start')
  end

  def state=(state)
    @context.set_variables({ 'State' => state })
  end

  def snow_release_id
    return @context.variable('ReleaseId', nil)
  end

  def snow_release_id=(release_id)
    @context.set_variables({ 'ReleaseId' => release_id })
  end

  def snow_change_id
    @context.variable('ChangeId', nil)
  end

  def snow_change_id=(change_id)
    @context.set_variables({ 'ChangeId' => change_id })
  end

  def snow_build_user
    @context.variable('BuildUser', nil)
  end

  def set_trend_dsm_url_details(name)
    Context.component.set_variables("pipeline", {
      "TrendAWSUrl" => name,
    })
  end

  def set_trend_dsm_tenant_id_details(name)
    Context.component.set_variables("pipeline", {
      "TrendTenantID" => name,
    })
  end

  def set_trend_dsm_token_details(name)
    Context.component.set_variables("pipeline", {
      "TrendTokenId" => name,
    })
  end

  def set_trend_dsm_saas_proxy_details(name)
    Context.component.set_variables("pipeline", {
      "TrendSAASProxy" => name,
    })
  end

  def set_trend_agent_activation_url_details(name)
    Context.component.set_variables("pipeline", {
      "DSAgentActivationUrl" => name,
    })
  end

  def snow_build_user=(build_user)
    @context.set_variables({ 'BuildUser' => build_user })
  end

  def flush
    @context.flush
  end
end
