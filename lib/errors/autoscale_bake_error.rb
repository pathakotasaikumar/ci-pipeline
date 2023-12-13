module Qantas
  module Pipeline
    module Errors
      # a custom error type to handle aws/autoscale AMI bake errors
      class AutoScaleBakeError < PipelineError
        def initialize(message = nil, e = nil)
          @description = "aws/autoscale component failed to bake AMI, check 'aws/autoscale failures' page"

          @help_link   = 'https://confluence.qantas.com.au/pages/viewpage.action?pageId=114798610'
          @id          = 101

          super(message, e)
        end
      end
    end
  end
end
