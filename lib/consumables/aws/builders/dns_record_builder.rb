require_relative "route53_record_builder"

module DnsRecordBuilder
  include Route53RecordBuilder

  # Generates template for Route53 Release record based on the component name
  # @param template [Hash] CloudFormation template reference
  def process_release_r53_dns_record(
    template:,
    zone:,
    component_name:
  )
    dns_name = Defaults.release_dns_name(
      component: component_name,
      zone: Defaults.dns_zone
    )

    _process_route53_records(
      template: template,
      record_sets: {
        "#{component_name}ReleaseDns".gsub(/[^a-zA-Z0-9]/, '') => {
          "Properties" => {
            "Name" => dns_name,
            "HostedZoneName" => zone,
            "Type" => "CNAME",
            "TTL" => "60",
            "ResourceRecords" => [
              Context.component.variable(component_name, 'DeployDnsName')
            ]
          }
        }
      }
    )
    Log.output "#{component_name} DNS: #{dns_name}"
  end

  # Updates reference template with Route53 resource record resources
  # @param template [Hash] Reference to a template
  def _process_deploy_r53_dns_records(
    template:,
    zone:,
    component_name:,
    resource_records:,
    type: 'CNAME',
    ttl: '60'
  )

    dns_name = Defaults.deployment_dns_name(
      component: component_name,
      zone: Defaults.dns_zone
    )

    Log.output("#{component_name} DNS: #{dns_name}")

    _process_route53_records(
      template: template,
      record_sets: {
        'DeployDns' => {
          'Properties' => {
            'Name' => dns_name,
            'HostedZoneName' => zone,
            'Type' => type,
            'TTL' => ttl,
            'ResourceRecords' => resource_records
          }
        }
      }
    )
  end

  # Executes update commands against AD DNS servers
  def deploy_ad_dns_records(dns_name:, endpoint:, type:, ttl: '60')
    Log.debug "Deploying AD DNS records"
    Util::Nsupdate.create_dns_record(dns_name, endpoint, type, ttl)

    is_wildcard_cerfificate_used = Context.component.variable(@component_name, 'WildcardCertifiateIsUsed', nil)
    unless is_wildcard_cerfificate_used.nil?
      custom_dns_name = Defaults.custom_dns_name(
        dns_name: dns_name,
        zone: Defaults.ad_dns_zone
      )
      Util::Nsupdate.create_dns_record(custom_dns_name, endpoint, type, ttl)
      Log.output("#{@component_name} Custom_DNS: #{custom_dns_name}")
    end

    Log.debug("#{@component_name} AWS DNS: #{endpoint}")
    Log.output("#{@component_name} DNS: #{dns_name}")
  end

  # Create release DNS records in AD DNS zone
  def create_ad_release_dns_records(component_name:)
    dns_name = Defaults.release_dns_name(
      component: component_name,
      zone: Defaults.ad_dns_zone
    )

    # Obtain DNS deployment dns name from context
    endpoint = Context.component.variable(component_name, 'DeployDnsName')

    Util::Nsupdate.create_dns_record(dns_name, endpoint, "CNAME", 60)
    is_wildcard_cerfificate_used = Context.component.variable(component_name, 'WildcardCertifiateIsUsed', nil)

    unless is_wildcard_cerfificate_used.nil?
      custom_dns_name = Defaults.custom_dns_name(
        dns_name: dns_name,
        zone: Defaults.ad_dns_zone
      )
      Util::Nsupdate.create_dns_record(custom_dns_name, dns_name, "CNAME", 60)
      Log.output "#{component_name} Custom_DNS: #{custom_dns_name}" if Defaults.ad_dns_zone?
    end

    Log.output "#{component_name} DNS: #{dns_name}" if Defaults.ad_dns_zone?
  end

  # Clean up deployment DNS record in AD DNS zone
  def _clean_ad_deployment_dns_record(component_name)
    # Skip clean up of records unless AD dns zone is used or global teardown
    return unless Defaults.ad_dns_zone? || Context.environment.variable('custom_buildNumber', nil)

    dns_name = Defaults.deployment_dns_name(
      component: component_name,
      zone: Defaults.ad_dns_zone
    )

    is_wildcard_cerfificate_used = Context.component.variable(component_name, 'WildcardCertifiateIsUsed', nil)
    unless is_wildcard_cerfificate_used.nil?
      custom_dns_name = Defaults.custom_dns_name(
        dns_name: dns_name,
        zone: Defaults.ad_dns_zone
      ) unless dns_name.nil?

      Util::Nsupdate.delete_dns_record(custom_dns_name) unless custom_dns_name.nil?
    end

    Util::Nsupdate.delete_dns_record(dns_name) unless dns_name.nil?
  rescue => error
    Log.error "Failed to delete deployment DNS record #{dns_name} or #{custom_dns_name} - #{error}"
    raise "Failed to delete deployment DNS record #{dns_name} - or #{custom_dns_name} -#{error}"
  end

  # Clean up release DNS record if required
  def _clean_ad_release_dns_record(component_name)
    return unless Context.persist.released_build? || Context.persist.released_build_number.nil?

    dns_name = Defaults.release_dns_name(
      component: component_name,
      zone: Defaults.ad_dns_zone
    )

    is_wildcard_cerfificate_used = Context.component.variable(component_name, 'WildcardCertifiateIsUsed', nil)
    unless is_wildcard_cerfificate_used.nil?
      custom_dns_name = Defaults.custom_dns_name(
        dns_name: dns_name,
        zone: Defaults.ad_dns_zone
      ) unless dns_name.nil?

      Util::Nsupdate.delete_dns_record(custom_dns_name) unless custom_dns_name.nil?
    end

    Util::Nsupdate.delete_dns_record(dns_name) unless dns_name.nil?
  rescue => error
    Log.error "Failed to delete release DNS record #{dns_name} or #{custom_dns_name} - #{error}"
    raise "Failed to delete release DNS record #{dns_name} or #{custom_dns_name} - #{error}"
  end

  # @return [Hash] Deploy and Release DNS records for the component
  def custom_name_records(component_name:, content:, pattern:)
    deploy_dns_name = Defaults.deployment_dns_name(
      component: component_name,
      zone: Defaults.dns_zone
    )
    release_dns_name = Defaults.release_dns_name(
      component: component_name,
      zone: Defaults.dns_zone
    )
    name_records = {
      'DeployDnsName' => deploy_dns_name,
      'ReleaseDnsName' => release_dns_name
    }

    if content.any?
      if Context.component.deep_find_variable(content: content, pattern: pattern)
        name_records["CustomDeployDnsName"] = Defaults.custom_dns_name(
          dns_name: deploy_dns_name,
          zone: Defaults.dns_zone
        )

        name_records["CustomReleaseDnsName"] = Defaults.custom_dns_name(
          dns_name: release_dns_name,
          zone: Defaults.dns_zone
        )
      end
    end

    return name_records
  end
end
