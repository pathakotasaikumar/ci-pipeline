require 'mustache'

class MustacheProcessor < Mustache
  def initialize(template_path)
    self.template_path = template_path
  end
end
