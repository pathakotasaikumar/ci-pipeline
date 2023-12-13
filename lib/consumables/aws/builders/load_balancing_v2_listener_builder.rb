require 'util/json_tools'

# Create AWS::LoadBalancingV2::Listener resource
module LoadBalancingV2ListenerBuilder
  # Generate AWS::LoadBalancingV2::Listener resource
  # @param template [Hash] CloudFormation template passed in as reference
  # @param listener_definition [Hash] Listener resource parsed from YAML definition
  # @param load_balancer [String] Reference to an associated AWS::LoadBalancingV2::LoadBalancer resource
  def _process_load_balancing_v2_listener(
    template:,
    listener_definition:,
    load_balancer:
  )

    listener_definition.each do |name, definition|
      default_actions = JsonTools.get(definition, 'Properties.DefaultActions', [])

      raise ArgumentError, 'DefaultActions must be exactly one value' if default_actions.size != 1

      default_actions = default_actions.first

      if default_actions['TargetGroupArn'].is_a?(String)
        default_actions['TargetGroupArn'] = { 'Ref' => default_actions['TargetGroupArn'] }
      end

      load_balancer = { 'Ref' => load_balancer } if load_balancer.is_a?(String)
      certificates = JsonTools.get(definition, 'Properties.Certificates', [])
      certificates = _process_certificates(certificates: certificates)
      template['Resources'][name] = {
        'Type' => 'AWS::ElasticLoadBalancingV2::Listener',
        'Properties' => {
          'DefaultActions' => [default_actions],
          'LoadBalancerArn' => load_balancer,
          'Port' => JsonTools.get(definition, 'Properties.Port'),
          'Protocol' => JsonTools.get(definition, 'Properties.Protocol'),
        }
      }

      resource = template['Resources'][name]
      resource['Properties']['Certificates'] = certificates unless certificates.empty?
      JsonTools.transfer(definition, 'Properties.SslPolicy', resource)
    end
  end

  def _process_certificates(certificates:)
    return [] if certificates.nil? || certificates.empty?

    alb_certificates = []
    certificates.each do |certificate|
      unless certificate["CertificateArn"].nil?
        sslCertificateId = certificate["CertificateArn"]
        unless Defaults.verify_certificate_alias(certificateAlias: sslCertificateId).nil?
          raise "Wrong alias value #{sslCertificateId} is specified for" \
                    " CertificateArn property" unless '@wildcard-qcpaws' == sslCertificateId

          certificate_name = if Defaults.is_prod?
                               Defaults.prod_wildcard_qcpaws_certificate_name
                             else
                               Defaults.nonp_wildcard_qcpaws_certificate_name
                             end
          #certificate_arn = "arn:aws:iam::#{Context.environment.account_id}:server-certificate/#{certificate_name}"
          Log.info "Replacing the certificate alias #{sslCertificateId.inspect} with the certificate from ACM Wildcard store"
          Context.component.set_variables(@component_name, 'WildcardCertifiateIsUsed' => 'true')
          certificate["CertificateArn"] = "{{resolve:ssm:/qcp/acm_certificate_arn}}"
        end
      end
      alb_certificates.push(certificate)
    end
    return alb_certificates
  end
end
