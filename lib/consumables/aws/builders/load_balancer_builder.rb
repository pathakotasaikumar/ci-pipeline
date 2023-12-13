require "util/json_tools"

module LoadBalancerBuilder
  def _process_load_balancer(
    template: nil,
    load_balancer_definition: nil,
    security_group_ids: nil
  )
    name, definition = load_balancer_definition.first

    scheme = JsonTools.get(definition, "Properties.Scheme", "internal")
    subnet_alias = JsonTools.get(definition, "Properties.Subnets", scheme == "internet-facing" ? "@public" : "@private")
    subnet_ids = Context.environment.subnet_ids(subnet_alias)

    listeners = JsonTools.get(definition, "Properties.Listeners", [])
    listeners = _process_listeners(listeners: listeners)

    template["Resources"][name] = {
      "Type" => "AWS::ElasticLoadBalancing::LoadBalancer",
      "Properties" => {
        "ConnectionDrainingPolicy" => {
          "Enabled" => JsonTools.get(definition, "Properties.ConnectionDrainingPolicy.Enabled", "true"),
          "Timeout" => JsonTools.get(definition, "Properties.ConnectionDrainingPolicy.Timeout", "60"),
        },
        "CrossZone" => "true",
        "HealthCheck" => {
          "HealthyThreshold" => JsonTools.get(definition, "Properties.HealthCheck.HealthyThreshold", 2).to_s,
          "Interval" => JsonTools.get(definition, "Properties.HealthCheck.Interval", 60).to_s,
          "Target" => JsonTools.get(definition, "Properties.HealthCheck.Target", "HTTP:80/"),
          "Timeout" => JsonTools.get(definition, "Properties.HealthCheck.Timeout", 5).to_s,
          "UnhealthyThreshold" => JsonTools.get(definition, "Properties.HealthCheck.UnhealthyThreshold", 2).to_s,
        },
        "Listeners" => listeners,
        "Scheme" => scheme,
        "SecurityGroups" => security_group_ids,
        "Subnets" => subnet_ids,
        "Policies" => JsonTools.get(definition, "Properties.Policies", []),
      }
    }

    # Set LB Cookie stickiness policy if specified
    resource = template["Resources"][name]
    JsonTools.transfer(definition, "Properties.LBCookieStickinessPolicy", resource)
    JsonTools.transfer(definition, "Properties.AppCookieStickinessPolicy", resource)

    # Add optional IdleTimeout parameter
    idle_timeout = JsonTools.get(definition, "Properties.ConnectionSettings.IdleTimeout", nil)
    unless idle_timeout.nil?
      template["Resources"][name]["Properties"]["ConnectionSettings"] ||= {}
      template["Resources"][name]["Properties"]["ConnectionSettings"]["IdleTimeout"] = idle_timeout
    end

    # Outputs
    template["Outputs"]["#{name}DNSName"] = {
      "Description" => "ELB endpoint address",
      "Value" => { "Fn::GetAtt" => [name, "DNSName"] }
    }
  end

  def _process_listeners(listeners:)
    return [] if  listeners.nil? || listeners.empty?

    elb_listeners = []
    listeners.each do |configuration|
      unless configuration["SSLCertificateId"].nil?
        sslCertificateId = configuration["SSLCertificateId"]
        unless Defaults.verify_certificate_alias(certificateAlias: sslCertificateId).nil?
          raise "Wrong alias value #{sslCertificateId} is specified for" \
                    " SSLCertificateId property" unless '@wildcard-qcpaws' == sslCertificateId

          certificate_name = if Defaults.is_prod?
                               Defaults.prod_wildcard_qcpaws_certificate_name
                             else
                               Defaults.nonp_wildcard_qcpaws_certificate_name
                             end
          #certificate_arn = "arn:aws:iam::#{Context.environment.account_id}:server-certificate/#{certificate_name}"
          Log.info "Replacing the certificate alias #{sslCertificateId.inspect} with the certificate from ACM Wildcard store"
          Context.component.set_variables(@component_name, 'WildcardCertifiateIsUsed' => 'true')
          configuration["SSLCertificateId"] = "{{resolve:ssm:/qcp/acm_certificate_arn}}"
        end
      end
      elb_listeners.push(configuration)
    end
    return elb_listeners
  end
end