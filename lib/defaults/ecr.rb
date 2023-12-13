module Defaults
  module Ecr
    extend self

    # Returns Qantas API Gateway admin username
    # @return [String] Api gateway admin registration username
    def ecr_registry
      Context.environment.variable('ecr_registry', "221295517176.dkr.ecr.ap-southeast-2.amazonaws.com")
    end

    # @param component_name [String] component name
    # @return [String] component build-level stack name
    def ecr_repository_name(component_name)
      [
        sections[:ams],
        sections[:qda],
        sections[:as]
      ].join('-').gsub(/[^a-zA-Z0-9\-]/, '-')
    end

    # @param component_name [String] component name
    # @return [String] component build-level stack name
    def ecr_latest_image_tag(component_name, build_override=nil)
      build = build_override.blank? ? sections[:build] : build_override
      [
        sections[:ams],
        sections[:qda],
        sections[:as],
        sections[:branch],
        component_name,
        build
      ].join('-').gsub(/[^a-zA-Z0-9\-]/, '-')
    end

    def ecr_access_org_list
      orgs = Context.environment.variable('ecr_access_org_list', "o-zqzhi53g09")
      return orgs.to_s.strip.split(',')
    end

    def ecr_default_policy()
      {
        "Version" => "2008-10-17",
        "Statement" => [
          {
            "Sid" => "AllowPull",
            "Effect" => "Allow",
            "Principal" => "*",
            "Action" => [
              "ecr:BatchCheckLayerAvailability",
              "ecr:BatchGetImage",
              "ecr:GetDownloadUrlForLayer"
            ],
            "Condition" => {
              "StringEquals" => {
                "aws:PrincipalOrgID" => ecr_access_org_list
              }
            }
          }
        ]
      }
    end
  end
end 
