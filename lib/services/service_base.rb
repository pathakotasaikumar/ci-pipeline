module Qantas
  module Pipeline
    module Services
      class ServiceBase
        def name
          self.class.to_s
        end

        def description
          'A base class for pipeline-specific services'
        end
      end
    end
  end
end
