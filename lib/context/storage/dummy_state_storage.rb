class DummyStateStorage
  def initialize()
    @context = {}
  end

  def load(context_path)
    Log.debug "Loading dummy state storage #{context_path}"
    return @context[context_path]
  end

  def save(context_path, variables)
    Log.debug "Saving dummy state storage #{context_path}"
    @context[context_path] = variables
  end
end
