# Helper class for detecting target OS
# taken from http://stackoverflow.com/questions/170956/how-can-i-find-which-operating-system-my-ruby-program-is-running-on/12937724
# potentially, we can consider using 'Platform' gem later on - http://rubygems.rubyforge.org/rubygems-update/Gem/Platform.html
module Util
  module OS
    extend self

    # Checks if current OS is windows
    def windows?(ruby_platform = RUBY_PLATFORM)
      raise 'ruby_platform should not be nil' if ruby_platform.nil?
      raise 'ruby_platform should be a string' unless ruby_platform.is_a?(String)

      !(/cygwin|mswin|mingw|bccwin|wince|emx/ =~ ruby_platform).nil?
    end

    # Checks if current OS is Mac
    def mac?(ruby_platform = RUBY_PLATFORM)
      raise 'ruby_platform should not be nil' if ruby_platform.nil?
      raise 'ruby_platform should be a string' unless ruby_platform.is_a?(String)

      !(/darwin/ =~ ruby_platform).nil?
    end

    # Checks if current OS is unix
    def unix?(ruby_platform = RUBY_PLATFORM)
      !windows?(ruby_platform)
    end

    # Checks if current OS is Linux
    def linux?(ruby_platform = RUBY_PLATFORM)
      unix?(ruby_platform) && !mac?(ruby_platform)
    end
  end
end
