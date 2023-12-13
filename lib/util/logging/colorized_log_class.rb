require 'date'
require_relative 'colorized_log_class.rb'

class ColorizedLogClass < BaseLogClass
  def initialize
    super
    _default_stdout.sync = true
  end

  def name
    "colorized_output"
  end

  private

  def _should_output_message?(method:, message:)
    # be aware that message: can be of any type - string, object, hash
    message != nil
  end

  def _output(method, message)
    color_code = _prepare_color(method: method, message: message)
    composed_message = _compose_message(method: method, message: message, color_code: color_code)

    if _should_output_message?(method: method, message: message)

      # backward compatibility with current Bamboo trace
      # these levels get traced to stderr so that Bamboo would show summary in build page
      if (method == :output || method == :error || method == :fatal)
        _default_stderr_message(message: composed_message)
      else
        _default_stdout_message(message: composed_message)
      end
    end
  end

  def _compose_message(method:, message:, color_code:)
    thred_id = _prepare_thred_id
    time_stamp = _prepare_timestamp(format: _time_format)

    # call to the base class
    # _prepare_message will mask :splunk_http data
    method_value = _prepare_method(method: method)
    message_value = _prepare_message(message: message, method: method)

    if (_should_add_color?(config: get_config, method: method, message: message))
      return "\e[#{color_code}m#{thred_id} #{time_stamp} #{method_value} #{message_value}\e[0m"
    end

    return "#{thred_id} #{time_stamp} #{method_value} #{message_value}"
  end

  def _get_default_config
    {
      "color_map" => {
        "method" => {
          "debug" => _light_blue,

          "info" => _green,
          "output" => _blue,

          "warn" => _yellow,
          "error" => _red,
          "fatal" => _red,

          "snow" => _pink,
          "splunk" => _pink
        }
      }
    }
  end

  def _should_add_color?(config:, method:, message:)
    result = true

    exclude_section = config.fetch("exclude", [])

    exclude_section.each do |exclude_config|
      if (exclude_config["type"] == "method")
        result = !_exclude_by_method?(method_exclude: exclude_config, method: method, message: message)
      end
    end

    result
  end

  def _exclude_by_method?(method_exclude:, method:, message:)
    result = false
    method_value = method.to_s.downcase

    if (method_value == method_exclude["value"])
      result = true
    end

    result
  end

  def _lookup_color_from_config(config:, method:, message:)
    color = nil

    color_map_section = config["color_map"]
    method_section = color_map_section["method"]

    method_value = method.to_s.downcase
    color = method_section.fetch(method_value, nil)

    color
  end

  def _lookup_color_for_method(method:, message:)
    color = _white

    begin
      # lookup color from custom config
      color = _lookup_color_from_config(config: get_config, method: method, message: message)
    rescue => exception
      _default_stdout_message(message: "Coudn't load color map from custom config: #{get_config}. Error: #{exception}")
      # and fallback to _white if nothing found in default config
      color = _white
    end

    color
  end

  def _prepare_color(method:, message:)
    _lookup_color_for_method(method: method, message: message)
  end

  def _white
    37
  end

  def _red
    31
  end

  def _green
    32
  end

  def _yellow
    33
  end

  def _blue
    34
  end

  def _pink
    35
  end

  def _light_blue
    36
  end

  def _gray
    37
  end
end
