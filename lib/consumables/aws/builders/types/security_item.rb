class SecurityItem
  attr_reader :name
  attr_reader :component

  def initialize(name: nil, component: nil)
    @name = name
    @component = component
  end
end

class SgSecurityItem < SecurityItem
  attr_reader :vpc_id

  def initialize(name: nil, component: nil, vpc_id: nil)
    super(name: name, component: component)
    @vpc_id = vpc_id
  end
end

class RoleSecurityItem < SecurityItem
  attr_reader :trust

  def initialize(name: nil, component: nil, trust: nil)
    super(name: name, component: component)
    @trust = trust
  end
end
