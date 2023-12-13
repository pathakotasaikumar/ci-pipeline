# Module responsible for QCP-specific actions

require 'digest'
require 'defaults/backup'
require 'defaults/snow'
require 'defaults/splunk'
require 'defaults/qualys'
require 'defaults/parameters'
require 'defaults/api_gateway'
require 'defaults/datadog'
require 'defaults/environment'
require 'defaults/nsupdate'
require 'defaults/longlived'
require 'util/nsupdate'
require 'defaults/public_s3_content'
require 'defaults/trend'
require 'defaults/veracode'
require 'defaults/wildcard_certificate'
require 'defaults/bamboo'
require 'defaults/ecr'

# Helper class used for QCP specific defaults and actions
module Defaults
  include ApiGateway
  include Backup
  include Environment
  include Qualys
  include Parameters
  include PublicS3Content
  include Splunk
  include Snow
  include Datadog
  include Nsupdate
  include Trend
  include Veracode
  include WildCardCertificate
  include Longlived
  include Bamboo
  include Ecr

  extend self

  # Checks indication that instance component uses windows images
  # @param definition [Hash] target definition
  def _codedeploy_win_instance?(definition:)
    # looking for the first hash with Type = "AWS::EC2::Instance"
    # this is aws/instance definition under Configuration
    config_section   = definition["Configuration"]
    instance_section = _find_component_definition(definition: definition, component_type: "AWS::EC2::Instance")

    if instance_section.nil?
      return false
    end

    image_id = JsonTools.get(instance_section, "Properties.ImageId", nil)

    if image_id.nil?
      return false
    end

    return image_id.include?("win")
  end

  # Checks indication that autoscale component uses windows images
  # @param definition [Hash] target definition
  def _codedeploy_win_autoscale?(definition:)
    # looking for AWS::EC2::Instance and AWS::AutoScaling::LaunchConfiguration objects
    bake_section   = _find_component_definition(definition: definition, component_type: "AWS::EC2::Instance")
    launch_section = _find_component_definition(definition: definition, component_type: "AWS::AutoScaling::LaunchConfiguration")

    bake_image_id = nil
    launch_image_id = JsonTools.get(launch_section, "Properties.ImageId", nil)

    if !bake_section.nil?
      bake_image_id = JsonTools.get(bake_section, "Properties.ImageId", nil)
    end

    # default
    if bake_image_id.nil? && launch_image_id.nil?
      return false
    end

    if (bake_image_id.nil? != true && bake_image_id.include?("win"))
      return true
    end

    if (launch_image_id.nil? != true && launch_image_id.include?("win"))
      return true
    end

    return false
  end

  def _find_component_definition(definition:, component_type:)
    config_section    = definition["Configuration"]
    component_section = config_section.select { |name, value| value.fetch('Type', nil) == component_type }

    if component_section.nil?
      return nil
    end

    return component_section.values.first
  end

  # Checks indication that component uses windows images
  # Supports instance, autoscale and autoheal - checks instance pros, bake props and launch configiration props
  # CodeDeploy uses this method to figure out zip/tar revision package format
  # returns [Boolean] if target definition is a windows-based component
  def codedeploy_win_component?(definition: nil)
    if definition.nil?
      return false
    end

    type = definition["Type"].downcase

    case type
    when "aws/instance"
      _codedeploy_win_instance?(definition: definition)
    when "aws/autoscale"
      _codedeploy_win_autoscale?(definition: definition)
    when "aws/autoheal"
      _codedeploy_win_autoscale?(definition: definition)
    else
      raise "Unsupported component type for CodeDeploy: #{type}"
    end
  end

  # returns [String] current deployment mode type as ENV['bamboo_deploy_mode']
  def _deployment_mode
    deployment_mode = ENV['bamboo_deploy_mode']
    deployment_mode
  end

  def _codedeploy_flag
    deployment_mode = ENV['bamboo_codedeploy']
    !deployment_mode.nil? && !deployment_mode.to_s.empty?
  end

  # returns [Boolean] is current deployment mode is "CodeDeploy"
  def is_codedeploy_deployment_mode?
    is_code_deploy = (_deployment_mode == 'code_deploy' || _codedeploy_flag == true)
    is_code_deploy
  end

  def sections
    @@sections
  end

  def set_sections(plan_key, branch_name = nil, build_number = nil, environment = nil)
    plan_key_split = plan_key.downcase.match(/([a-z0-9]+)-([a-z][0-9]+)s([0-9]+)([a-z]*)([0-9]*)/)

    if plan_key_split.nil?
      raise "Unable to retrieve sections for plan key #{plan_key.inspect}, it is not in the standard format"
    end

    environment = if environment.nil? || environment.empty?
                    get_environment_from_plan_key(plan_key)
                  else
                    environment.downcase.start_with?('prod') ? 'prod' : 'nonp'
                  end

    _update_section(
      plan_key_split: plan_key_split,
      environment: environment,
      branch_name: branch_name,
      build_number: build_number
    )
  end

  def _update_section(plan_key_split:, environment:, branch_name:, build_number:)
    @@sections = {
      ams: plan_key_split[1],
      qda: plan_key_split[2],
      as: plan_key_split[3],
      ase: plan_key_split[4].empty? ? "prod" : plan_key_split[4],
      ase_number: plan_key_split[5],
      plan_key: plan_key.downcase,
      branch: (branch_name || ""),
      build: (build_number || ""),
      env: environment,
      asbp_type: (plan_key_split[2].start_with? 'p') ? 'ps' : 'qda'
    }.freeze
  end

  # @return [String] application environment - prod or nonp
  def get_environment_from_plan_key(plan_key)
    matches = plan_key.downcase.match(/^.*[0-9]+([a-z]+)[0-9]*$/)
    if matches.nil?
      Log.warn "Cannot determine environment from the plan key #{plan_key.inspect}. Defaulting to 'prod'."
      environment = 'prod'
    else
      environment = matches[1] == 'prod' ? 'prod' : 'nonp'
      Log.info "Found ASE of '#{matches[1]}' in plan key. This is a '#{environment}' environment."
    end

    return environment
  end

  # @param component_name [String] component name
  # @param build [String] build number
  # @return [String] component name tag value
  def component_name_tag(component_name: nil, build: nil)
    build ||= sections[:build]
    tag = branch_specific_id.join('-')
    return "#{tag}-#{build}-#{component_name}"
  end

  def qda_specific_id(*extras)
    return [sections[:ams], sections[:qda]] + extras.compact
  end

  def as_specific_id(*extras)
    return qda_specific_id + [sections[:as]] + extras.compact
  end

  def env_specific_id(*extras)
    return as_specific_id + [sections[:env]] + extras.compact
  end

  def ase_specific_id(*extras)
    return as_specific_id + [sections[:ase]] + extras.compact
  end

  def branch_specific_id(*extras)
    return ase_specific_id + [sections[:branch]] + extras.compact
  end

  def build_specific_id(*extras)
    return branch_specific_id + [sections[:build]] + extras.compact
  end

  # @param component_name [String] component name
  # @return [Array] list of key value pairs for tags
  def get_tags(component_name = nil, scope = :build)
    tags = [
      { key: 'AMSID', value: sections[:ams].upcase },
      { key: 'EnterpriseAppID', value: sections[:qda].upcase },
      { key: 'ApplicationServiceID', value: sections[:as].upcase },
      { key: 'Environment', value: sections[:ase].upcase },
      { key: 'AsbpType', value: sections[:asbp_type].upcase }
    ]

    if scope == :build
      # Add per-build tags: name, branch name, and build number
      tags += [
        { key: 'Name', value: build_specific_id(component_name).join("-") },
        { key: 'Branch', value: sections[:branch] },
        { key: 'Build', value: sections[:build] }
      ]
    else
      # Add per-environment tags: name
      tags += [
        { key: 'Name', value: env_specific_id(component_name).join("-") }
      ]
    end

    project_code = nil
    if !Context.pipeline.snow_release_id.nil?
      tags << { key: 'ReleaseID', value: Context.pipeline.snow_release_id }
    elsif !project_code.nil?
      tags << { key: 'ProjectCode', value: project_code }
    end

    return tags
  end

  # @param component_name [String] component name
  # @return [String] Snapshot identifier
  def snapshot_identifier(component_name: nil)
    [
      sections[:ams].upcase,
      sections[:qda].upcase,
      sections[:as],
      sections[:branch],
      sections[:build],
      component_name,
      Time.now.to_i
    ].join('-').gsub(/[^A-Za-z0-9-]/, '-')
  end

  # Generates unique URL based on tags to generate resources group in AWS console
  # @return [String] URL for resource group for use in AWS console
  def resource_group_url
    plan_key = "#{sections[:ams]}-#{sections[:qda]}S#{sections[:as]}#{sections[:ase]}".upcase
    name = "#{plan_key} #{sections[:branch]}"
    name = "#{name[0...29]}..." if name.length > 32

    query = {
      "name" => name,
      "regions" => ["ap-southeast-2"],
      "resourceTypes" => "all",
      "tagFilters" => [
        {
          "key" => "AMSID",
          "values" => [sections[:ams].upcase]
        },
        {
          "key" => "EnterpriseAppID",
          "values" => [sections[:qda].upcase]
        },
        {
          "key" => "ApplicationServiceID",
          "values" => [sections[:as].upcase]
        },
        {
          "key" => "Environment",
          "values" => [sections[:ase].upcase]
        },
        {
          "key" => "Branch",
          "values" => [sections[:branch]]
        }
      ]
    }

    "https://resources.console.aws.amazon.com/r/group#sharedgroup=#{JSON.dump(query)}"
  end

  # Generate Hash of build specific values
  # @param plan_key [String] Bamboo plan key
  # @param branch_name [String] Bamboo branch name
  # @param build_number [String] Bamboo build number
  # @param environment [String] Bamboo environment variable
  # @return [Hash] Associative array of QCP specific values
  #   AMS, QDA, AS, ASE, ASE_NUMBER, PLAN_KEY, BRANCH, BUILD, ENV, ASBP_TYPE
  def get_sections(plan_key, branch_name = nil, build_number = nil, environment = nil)
    plan_key_split = plan_key.downcase.match(/([a-z0-9]+)-([a-z][0-9]+)s([0-9]+)([a-z]*)([0-9]*)/)
    if plan_key_split.nil?
      raise "Unable to retrieve sections for plan key #{plan_key.inspect}, it is not in the standard format"
    end

    if environment.nil? || environment.empty?
      environment = Defaults.get_environment_from_plan_key(plan_key)
    elsif environment.downcase.start_with? 'prod'
      environment = 'prod'
    else
      environment = 'nonp'
    end

    {
      ams: plan_key_split[1],
      qda: plan_key_split[2],
      as: plan_key_split[3],
      ase: plan_key_split[4].empty? ? "prod" : plan_key_split[4],
      ase_number: plan_key_split[5],
      plan_key: plan_key.downcase,
      branch: (branch_name || ""),
      build: (build_number || ""),
      env: environment,
      asbp_type: (plan_key_split[2].start_with? 'p') ? 'ps' : 'qda'
    }
  end

  # Return default inbound rules
  # @return [String] CIDR block for default network inbound rules to be applied to all components
  def default_inbound_sources
    inbound_sg = []

    linux_sg = Context.environment.variable('bastion_linux_sg_id', 'sg-2f36124b')
    win_sg = Context.environment.variable('bastion_windows_sg_id', 'sg-e2383085')

    Log.info "Finding bastion security_groups"
    Log.info "#{linux_sg}"
    Log.info "#{win_sg}"

    inbound_sg = [linux_sg, win_sg]

    return inbound_sg
  end

  # @return [Array] list of default ports allowed in
  def default_inbound_ports
    %w(
      TCP:22
      TCP:3389
    )
  end

  # QCPP-1103 Qualys PreAuth Scanner
  # @return [Array] list of SG where Qualys lives
  def default_qualys_sources
    Log.info "Finding default_qualys_sources security_groups"
    return [Context.environment.variable('qualys_sg_id', 'sg-0cdb1a5e7cefd3dbd')]
  end

  # @param component_name [String] component name
  # @return [String] The CI artefact path within the artefact bucket
  def ci_artefact_path(component_name: nil)
    path = "ci/#{sections[:ams]}/#{sections[:qda]}/#{sections[:as]}/#{sections[:branch]}/latest"
    path = "#{path}/#{component_name}".downcase unless component_name.nil?

    return path
  end

  # @param component_name [String] component name
  # @return [String] The CI artefact path within the artefact bucket
  def ci_versioned_artefact_path(component_name: nil, build_number:)
    path = "ci/#{sections[:ams]}/#{sections[:qda]}/#{sections[:as]}/#{sections[:branch]}/#{build_number}"
    path = "#{path}/#{component_name}".downcase unless component_name.nil?

    return path
  end

  # @param component_name [String] component name
  # @return [String] CD artefact path within the artefact bucket
  def cd_artefact_path(component_name: nil)
    path = [
      'cd',
      sections[:ams],
      sections[:qda],
      sections[:as],
      sections[:ase],
      sections[:branch],
      sections[:build]
    ].join('/')

    path = "#{path}/#{component_name}" unless component_name.nil?

    return path
  end

  # @param component_name [String] component name
  # @return [String] CD common artefact path within the artefact bucket
  def cd_common_artefact_path(component_name: nil)
    path = [
      'cd',
      sections[:ams],
      sections[:qda],
      sections[:as],
      sections[:ase],
      sections[:branch],
      '00'
    ].join('/')

    path = "#{path}/#{component_name}" unless component_name.nil?

    return path
  end

  # @param component_name [String] component name
  # @param type [String] stage of deployment - bake or deploy
  # @return [String] CD artefact path within the artefact bucket
  def log_upload_path(component_name: nil, type: nil)
    path = [
      "logs",
      sections[:ams],
      sections[:qda],
      sections[:as],
      sections[:ase],
      sections[:branch],
      sections[:build],
    ].join('/')

    path = "#{path}/#{component_name}" unless component_name.nil?
    path = "#{path}/#{type}" unless type.nil?

    return path
  end

  # @return [String] Route53 DNS zoneup
  def ad_dns_zone
    'qcpaws.qantas.com.au'
  end

  # @return [String] Route53 DNS zone
  def r53_dns_zone
    'aws.qcp'
  end

  # Returns +default+ DNS zone
  # Bamboo environment variable 'bamboo_dns_zone' sets zone
  # Default zone is 'ad_dns_zone'
  # @return [String] DNS zone
  def dns_zone(zone: nil)
    zone || Context.environment.variable('dns_zone', ad_dns_zone)
  end

  def ad_dns_zone?
    dns_zone == ad_dns_zone
  end

  def r53_dns_zone?
    dns_zone == r53_dns_zone
  end

  def is_prod?
    sections[:env].downcase == "prod"
  end

  # Examine environment DNS zone.
  # If matches the default route 53 zone, then append ams and environment entries
  # else return zone as is (public route 53 zone)
  def r53_hosted_zone
    zone = dns_zone

    # If the ad dns zone is specified, then base on the default r53 zone
    zone = r53_dns_zone if ad_dns_zone?

    # If unknown dns zone specified then assume its a public dns zone within the account
    return zone unless zone == r53_dns_zone

    # Build qualified route 53 dns zone based on the environment supplied zone
    zone = sections[:env] == "nonp" ? "nonp.#{zone}" : zone
    "#{sections[:ams]}.#{zone}"
  end

  # @return [String] Application specific DNS zone
  def as_domain(zone: nil, separator: '.')
    zone = dns_zone if zone.nil?
    [
      sections[:ase],
      "#{sections[:qda]}-#{sections[:as]}",
      sections[:ams],
      sections[:env] == "nonp" ? "nonp.#{zone}" : zone
    ].join(separator)
  end

  def _resolve_ami_id_by_txt(record_name:)
    Log.debug "Checking DNS for AMI matching record #{record_name}"

    ami_id = nil

    Resolv::DNS.open do |dns|
      results = dns.getresources record_name, Resolv::DNS::Resource::IN::TXT
      ami_id = results[0].data if results.length == 1
    end

    ami_id
  end

  # @param record [String] DNS TXT record
  # @return [String] AMI ID references by DNS txt record
  def image_by_dns(record)
    record = "#{record}.#{dns_zone}" if record =~ /^[\w-]+\.[\w-]+\.[\w-]+\.[\w-]+\.[\w-]+(\.nonp)?$/
    return unless record.match(ad_dns_zone) || record.match(r53_dns_zone)

    ami_id = _resolve_ami_id_by_txt(record_name: record)
    return if ami_id.nil?

    Log.debug "Found AMI: #{ami_id} matching #{record}"
    ami_id
  end

  # @param record [String] DNS TXT record
  # @return [String] AMI ID references by DNS txt record
  def txt_by_dns(record, max_attempts = 5)
    record = "#{record}.#{dns_zone}" if record =~ /^[\w-]+\.[\w-]+\.[\w-]+\.[\w-]+\.[\w-]+(\.nonp)?$/

    # only allow resolution from the internal known DNS zones.
    return unless record.match(ad_dns_zone) || record.match(r53_dns_zone)

    result_record = nil

    attempts = 0
    while result_record.nil? || result_record.empty?
      raise "Exceeded maximum number of attempts" if attempts > max_attempts

      Resolv::DNS.open do |dns|
        results = dns.getresources(record, Resolv::DNS::Resource::IN::TXT)
        result_record = results[0].data if results.length == 1
      end
      attempts += 1
      sleep 1
    end

    Log.debug "Found record: #{result_record} matching #{record}"
    result_record
  end

  # @param component [String] component name
  # @param resource [String] component resource name
  #   Eg: DB Instance within DB cluster
  # @return [String] a build-level DNS name for use during component deployment
  #   Eg: component-resource.master-6.dev.c031-01.ams01.nonp.qcpaws.qantas.com.au
  def deployment_dns_name(
    component: nil,
    resource: nil,
    zone: nil
  )
    name = "#{sections[:branch]}-#{sections[:build]}.#{as_domain(zone: zone)}"
    component = "#{component}-#{resource}" unless resource.nil?
    return "#{component}.#{name}".downcase.gsub(/[^a-zA-Z0-9.\-]/, '-')
  end

  # @param dns_name [String] dns_name
  # @param zone [String] zone resource
  #   Eg: DB Instance within DB cluster
  # @return [String] a build-level DNS name for use during component deployment
  #   Eg: component-resource-master-6-dev-c031-01-ams01-nonp.qcpaws.qantas.com.au
  def custom_dns_name(
    dns_name:,
    zone:
  )
    split_pattern = ".#{zone}"
    name = dns_name.split(split_pattern).join('').gsub(/[^a-zA-Z0-9_]/, '-')
    raise "The Custom DNS record #{name}.#{zone} exceeds the max character limit of 63." \
              "Please use small branch name or component name." if name.length > 63
    return "#{name}.#{zone}"
  end

  # @param component [String] component name
  # @param resource [String] component resource name
  #   Eg: DB Instance within DB cluster
  # @return [String] a branch-level DNS name for use during component release
  #   Eg: component-resource.master.dev.c031-01.ams01.qcpaws.qantas.com.au
  def release_dns_name(
    component: nil,
    resource: nil,
    zone: nil
  )
    name = "#{sections[:branch]}.#{as_domain(zone: zone)}"
    component = "#{component}-#{resource}" unless resource.nil?
    return "#{component}.#{name}".downcase.gsub(/[^a-zA-Z0-9.\-]/, '-')
  end

  # @param component [String] component name
  # @param resource [String] component resource name
  #   Eg: DB Instance within DB cluster
  # @return [String] a branch-level DNS name for use during component release
  #   Eg: component-resource-master-dev-c031-01-ams01.qcpaws.qantas.com.au
  def custom_release_dns_name(
    component: nil,
    resource: nil,
    zone: nil
  )
    name = "#{sections[:branch]}-#{as_domain(zone: zone, separator: '-')}"
    component = "#{component}-#{resource}" unless resource.nil?
    return "#{component}-#{name}".downcase.gsub(/[^a-zA-Z0-9.\-]/, '-')
  end

  # @param source_image_name [String] source image name
  # @param component_name [String] component name
  # @return [String] an EC2 image name
  def image_name(source_image_name, component_name)
    release_id = Context.pipeline.snow_release_id || "NoRelease"

    [
      source_image_name,
      sections[:ams].upcase,
      sections[:qda].upcase,
      sections[:as],
      release_id,
      component_name,
      sections[:branch],
      sections[:build],
      Time.now.strftime('%s')
    ].join('-').gsub(/[^a-zA-Z0-9\[\].\-()\/@_]/, '').split(//).last(128).join
  end

  # @return [String] AS specific key alias name
  def kms_secrets_key_alias
    [
      "alias/#{sections[:ams]}",
      sections[:qda],
      sections[:as],
      sections[:env]
    ].join('-')
  end

  # @return [String] AS specific KMS stack name
  def kms_stack_name
    [
      sections[:ams],
      sections[:qda],
      sections[:as],
      sections[:env],
      'kms'
    ].join('-').gsub(/[^a-zA-Z0-9\-]/, '-')
  end

  # @return [String] qualys bootstrap stack name
  def qualys_kms_stack_name
    'qcp-qualys-bootstrap'
  end

  # @return [String] AS specific DNS stack name
  def dns_stack_name
    [
      sections[:ams],
      sections[:qda],
      sections[:as],
      sections[:branch],
      'ReleaseDns'
    ].join('-').gsub(/[^a-zA-Z0-9\-]/, '-')
  end

  # @param component_name [String] component name
  # @return [String] component build-level stack name
  def component_stack_name(component_name)
    [
      sections[:ams],
      sections[:qda],
      sections[:as],
      sections[:ase],
      sections[:branch],
      sections[:build],
      component_name
    ].join('-').gsub(/[^a-zA-Z0-9\-]/, '-')
  end

  # @param component_name [String] component name
  # @param resource_name [String] resource name
  # @return [String] component id, this is auto hash compact to maxlength char if it's too long
  def resource_name(component_name, resource_name, maxlength = 63)
    id = [
      sections[:ams],
      sections[:qda],
      sections[:as],
      sections[:ase],
      sections[:branch],
      sections[:build],
      component_name,
      resource_name,
    ].join('-').gsub(/[^a-zA-Z0-9\-]/, '-').downcase
    if id.length > maxlength
      return [
        sections[:ams],
        sections[:qda],
        sections[:as],
        sections[:ase],
        Digest::MD5.hexdigest(id)
      ].join('-').gsub(/[^a-zA-Z0-9\-]/, '-').downcase.to_s[0..maxlength]
    else
      return id
    end
  end

  # @param component_name [String] component name
  # @return [String] a component security build-level stack name
  def component_security_stack_name(component_name)
    [
      sections[:ams],
      sections[:qda],
      sections[:as],
      sections[:ase],
      sections[:branch],
      sections[:build],
      component_name,
      'Security'
    ].join('-').gsub(/[^a-zA-Z0-9\-]/, '-')
  end

  # @param component_name [String] component name
  # @return [String] a component build specific policu name
  def policy_name(component_name)
    [
      sections[:ams],
      sections[:qda],
      sections[:as],
      sections[:ase],
      sections[:branch],
      sections[:build],
      component_name
    ].join('-').gsub(/[^a-zA-Z0-9\-_]/, '-').split(//).last(128).join
  end

  # @param component_name [String] component name
  # @return [String] a build-level security rules stack name
  def security_rules_stack_name(component_name)
    [
      sections[:ams],
      sections[:qda],
      sections[:as],
      sections[:ase],
      sections[:branch],
      sections[:build],
      component_name,
      'Rules'
    ].join('-').gsub(/[^a-zA-Z0-9\-]/, '-')
  end

  # @param asir_set_name [String] ASIR Set name
  # @return [String] the ASIR source security group stack name
  def asir_source_group_stack_name(asir_set_name)
    [
      sections[:ams],
      sections[:qda],
      sections[:as],
      sections[:env],
      asir_set_name,
      'AsirSourceGroup'
    ].join('-').gsub(/[^a-zA-Z0-9\-]/, '-')
  end

  # @return [String] the ASIR destination security group stack name
  def asir_destination_group_stack_name
    [
      sections[:ams],
      sections[:qda],
      sections[:as],
      sections[:env],
      'AsirDestinationGroup'
    ].join('-').gsub(/[^a-zA-Z0-9\-]/, '-')
  end

  # @return [String] the ASIR destination security rules stack name
  def asir_destination_rules_stack_name
    [
      sections[:ams],
      sections[:qda],
      sections[:as],
      sections[:env],
      'AsirDestinationGroupRules'
    ].join('-').gsub(/[^a-zA-Z0-9\-]/, '-')
  end

  # @return [String] the ASIR managed policy stack name
  def asir_managed_policy_stack_name(asir_set_name)
    [
      sections[:ams],
      sections[:qda],
      sections[:as],
      sections[:env],
      asir_set_name,
      'AsirManagedPolicy'
    ].join('-').gsub(/[^a-zA-Z0-9\-]/, '-')
  end

  # @return [String] the AMS qcp (genesis) managed IAM stack
  def qcp_iam_ams_managed_stack_name
    return "qcp-iam-ams-managedpolicy"
  end


  def default_region
    "ap-southeast-2"
  end
end
