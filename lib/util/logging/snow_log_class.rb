require_relative 'base_log_class.rb'

class SnowLogClass < BaseLogClass
  def initialize
    super
  end

  def name
    "snow"
  end

  # override default implementation to avoid message propogation
  def _output(method, message)
  end

  # override snow call, redirect them to ServiceNow
  def snow(message)
    begin
      ServiceNow.log_message(message)
    rescue => e
      Log.error "Failed to log message to ServiceNow - #{e}"
    end
  end
end
