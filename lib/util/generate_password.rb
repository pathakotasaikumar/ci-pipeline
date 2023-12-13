class GeneratePassword
  def self.generate(length: 16, charset: 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789', silent: false)
    if silent != true
      Log.debug "Generating a #{length}-character password"
    end

    password = ''
    for i in 0...length do
      password += charset[rand(charset.length)]
    end

    return "#{password}"
  end
end
