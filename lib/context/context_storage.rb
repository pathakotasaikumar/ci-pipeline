class ContextStorage
  def initialize(
    name: nil,
    state_storage: nil,
    path: nil,
    sync: false
  )
    @name = name
    @state_storage = state_storage
    @context_path = path
    @sync = sync

    @mutex = Mutex.new if @sync

    @context = nil
    @loaded = false
    @modified = false
  end

  def has_key?(key)
    return _context.has_key? key
  end

  def [](key)
    return _context[key]
  end

  def []=(key, value)
    if _context[key] != value
      @modified = true
      _context[key] = value
    end

    return self
  end

  def variable(variable_name, default = :undef)
    return _context[variable_name] if _context.has_key? variable_name
    return default unless default == :undef

    raise "Could not find variable #{variable_name}, and no default was supplied."
  end

  def variables
    return _context.clone
  end

  def set_variables(variables)
    variables.each do |key, value|
      @modified = true if _context[key] != value
      _context[key] = value
    end

    return self
  end

  def flush
    if @modified and !@context.nil?
      Log.info "Saving #{@name} context"
      @state_storage.save(@context_path, @context)
      @modified = false
    end

    return self
  end

  def reload
    flush
    @loaded = false
    @context = nil
    return self
  end

  private def _context
    if @sync
      @mutex.synchronize do
        _load_context
      end
    else
      _load_context
    end

    return @context
  end

  private def _load_context
    if !@loaded
      Log.info "Loading #{@name} context"
      @context = (@state_storage.load(@context_path) || {})
      @loaded = true
    end
  end
end
