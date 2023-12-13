require 'date'
require_relative 'colorized_log_class.rb'

class TokenizedColorLogClass < ColorizedLogClass
  def initialize
    super
  end

  def name
    "tokenized_color_output"
  end

  def _get_default_config
    parent_config = super
    my_config = {
      "tokens" => {
        "restrict" => [
          # { "type" => "method", "value" => "debug" }
        ],
        "allow" => [
          { "type" => "contains_value", "value" => "Loading Rake" },

          { "type" => "method", "value" => "info" },
          { "type" => "method", "value" => "output" },
          { "type" => "method", "value" => "warn" },
        ]
      },
      "formatters" => [
        # add indent to all 'Loading Rake' messages
        { "type" => "contains_value", "value" => "Loading Rake", "format" => "    {0}" },
        # add indent to all debug messages, "{0}" is replaces with original message
        { "type" => "method", "value" => "debug", "format" => "    {0}" },
      ]
    }

    _merge_config(
      default_config: _deep_copy(parent_config),
      custom_config: _deep_copy(my_config)
    )
  end

  def _prepare_message(message:, method:)
    config = get_config
    config_formatters = config["formatters"]

    composed_message = super

    # never format splunk messages
    if method == :splunk_http || method == :splunk
      return composed_message
    end

    # other message types will be formetted
    composed_message = _format_message(message: message, method: method, formatters: config_formatters)

    composed_message
  end

  def _format_message(message:, method:, formatters:)
    result = message

    if (formatters == nil)
      return result
    end

    formatters.each do |formatter|
      if (formatter["type"] == "method")
        result = _process_method_formatter(message: message, method: method, formatter: formatter)
      end

      if (formatter["type"] == "contains_value")
        result = _process_contains_value_formatter(message: message, method: method, formatter: formatter)
      end
    end

    result
  end

  def _process_contains_value_formatter(message:, method:, formatter:)
    result = message

    if (result == nil || result.empty?)
      return ''
    end

    message_value = message.to_s.downcase
    formatter_value = formatter["value"].downcase

    if message_value.include? formatter_value
      result = formatter["format"].gsub("{0}", message)
    end

    result
  end

  def _process_method_formatter(message:, method:, formatter:)
    result = message
    method_value = method.to_s.downcase

    if (method_value == formatter["value"])
      result = formatter["format"].gsub("{0}", message)
    end

    result
  end

  # making a decision if a message needs to be logged
  def _should_output_message?(method:, message:)
    config = get_config
    config_tokens = config["tokens"]

    # check 'restrict' tokens
    restrict_result = _process_tokens(
      tokens: config_tokens["restrict"],
      method: method,
      message: message,
      allow: false
    )

    result = restrict_result

    # check 'allow' if there is a result on 'restrict' tokens
    # message might be allowed by 'allow' tokens
    if restrict_result != nil
      allow_result = _process_tokens(
        tokens: config_tokens["allow"],
        method: method,
        message: message,
        allow: true
      )

      if allow_result != nil
        result = allow_result
      end
    end

    # allow if no rules hit
    if result == nil
      return true
    end

    # return rule result
    result
  end

  def _process_tokens(tokens:, method:, message:, allow:)
    result = nil

    tokens.each do |token|
      if (token["type"] == "method")
        result = _process_method_token(token: token, method: method, message: message, allow: allow)
        break if result != nil
      end

      if (token["type"] == "contains_value")
        result = _process_contains_value_token(token: token, method: method, message: message, allow: allow)
        break if result != nil
      end
    end

    result
  end

  def _process_contains_value_token(token:, method:, message:, allow:)
    result = nil

    if (message == nil || message.empty?)
      return result
    end

    message_value = message.to_s.downcase
    token_value = token["value"].downcase

    if message_value.include? token_value
      result = allow
    end

    result
  end

  def _process_method_token(token:, method:, message:, allow:)
    result = nil
    method_value = method.to_s.downcase

    if (method_value == token["value"])
      result = allow
    end

    result
  end
end
