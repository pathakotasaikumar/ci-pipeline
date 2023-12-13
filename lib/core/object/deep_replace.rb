module Core
  module Object
    # Helper method for deep traversal of nested Hashes and Arrays
    module DeepReplace
      # Process strings with specified block within a nested structure
      # @param block [Block] Block to process against found strings
      def deep_replace(&block)
        raise "Method requires a block" unless block_given?

        case self
        when Hash
          each { |k, v| self[k] = v.deep_replace(&block) }
        when Array
          map { |v| v.deep_replace(&block) }
        when String
          yield(self)
        else
          self
        end
      end
    end
  end
end
