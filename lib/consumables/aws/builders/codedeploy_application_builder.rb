# Module creates  CloudFormation templates for CodeDeploy Application
module AwsCodeDeployApplicationBuilder
  # Creates a CloudFormation template for a new CodeDeploy application
  # @param template [Hash] CloudFormation template passed in as reference
  # @param resource_name [String] CloudFormation template resource name
  # @param application_name [String] CodeDeploy Application name
  def _process_codedeploy_application(
    template:,
    resource_name:,
    application_name:
  )
    if template.nil? || !template.is_a?(Hash)
      raise "template is expected to be a Hash - got #{template.class}"
    end

    template["Resources"][resource_name] = {
      "Type" => "AWS::CodeDeploy::Application",
      "Properties" => {
        "ApplicationName" => application_name
      }
    }

    template
  end
end
