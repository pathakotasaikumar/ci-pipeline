module Defaults
  module CustomTags
    extend self

    # @return [String] Value for CustomTags
    def Tags
      Context.environment.variable('Tags', nil)
    end
  end
end
