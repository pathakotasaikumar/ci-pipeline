class StringUtils
  def self.compare_upcase(s1, s2)
    raise "The passed arguments(#{s1.inspect} , #{s2.inspect}) contains one or more nil values." if s1.nil? or s2.nil?

    return s1.upcase == s2.upcase
  end

  def self.generate_string(length: 32, charset: 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789')
    result = ''
    for i in 0...length do
      result += charset[rand(charset.length)]
    end

    return "#{result}"
  end
end
