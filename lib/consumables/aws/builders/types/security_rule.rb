class SecurityRule
  def ==(o)
    o.class == self.class && o._state == _state
  end
end

class IpSecurityRule < SecurityRule
  attr_reader :sources
  attr_reader :destination
  attr_reader :ports
  attr_reader :name
  attr_reader :allow_cidr
  attr_reader :allow_direct_sg

  def initialize(sources: nil, destination: nil, ports: nil, name: nil, allow_cidr: false, allow_direct_sg: false)
    if destination.start_with? 'sg-' and allow_direct_sg == false
      raise "SecurityGroup id is not allowed on destination #{destination.inspect}, must specify with format \"<component>.<security item>\""
    end

    Array(sources).each do |source|
      if allow_cidr == false and source[0..0] =~ /[0-9]/
        raise "CIDR format is not allowed on source #{source.inspect}, must specify with format \"<component>.<security item>\""
      end
      if allow_direct_sg == false and source.start_with? 'sg-'
        raise "Security Group id is not allowed on source #{source.inspect}, must specify with format \"<component>.<security item>\""
      end
    end

    @sources = sources.nil? ? nil : Array(sources)
    @destination = destination
    @ports = Array(ports).uniq.map { |port| IpPort.from_specification(port) }
    @name = name
  end

  def _state
    [@sources, @destination, @ports]
  end
end

class IamSecurityRule < SecurityRule
  attr_reader :roles
  attr_reader :resources
  attr_reader :actions
  attr_reader :condition

  def initialize(roles: nil, resources: nil, actions: nil, condition: nil)
    @roles = roles.nil? ? nil : Array(roles)
    @resources = resources.nil? ? nil : Array(resources)
    @actions = Array(actions)
    @condition = condition
  end

  def _state
    [@roles, @resources, @actions, @condition]
  end
end

class IpPort
  include Comparable

  attr_reader :spec
  attr_reader :protocol
  attr_reader :from
  attr_reader :to

  def initialize(spec: nil, protocol: nil, from: nil, to: nil)
    @spec = spec
    @protocol = protocol
    @from = from
    @to = to
  end

  def ==(o)
    o.class == self.class && o._state == _state
  end

  def _state
    [@spec, @protocol, @from, @to]
  end

  def self.from_specification(specification)
    # Match port specification using regex
    matches = specification.downcase.match /^((?:tcp)|(?:udp)|(?:all)):((?:[0-9]+)|(?:\*))(?:-((?:[0-9]+)|(?:\*)))?$/
    raise "Invalid port specification #{specification.inspect}, must be <protocol>:<from_port>[-<to_port>]" if matches.nil?

    # Extract regex captures
    protocol = matches[1]
    protocol = "-1" if protocol == 'all'
    from_port = matches[2]
    to_port = matches[3] || matches[2]
    from_port = 0 if from_port == '*'
    to_port = 65535 if to_port == '*'

    # Ensure port range is valid
    raise "Invalid port range in #{port.inspect}: start port #{from_port.inspect} is greater than end port #{to_port.inspect}" if from_port.to_i > to_port.to_i

    return IpPort.new(spec: specification, protocol: protocol, from: from_port, to: to_port)
  end
end
