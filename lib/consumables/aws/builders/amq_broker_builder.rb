require 'util/json_tools'

# Module is responsible for generating Amazon MQ Broker CloudFormation resource
module AmqBrokerBuilder
  # Generate AWS::AmazonMQ::Broker resource
  # @param template [Hash] CloudFormation template passed in as reference
  # @param component_name [String] Logical name for associated MQ Broker resource
  # @param amq_broker [Hash] MQ Broker details parsed from component definition file
  # @param security_groups [Array] security groups details
  # @param amq_configuration [Hash] Aamazon MQ configuration details like Configuration ID and Revision
  # @param subnet_ids [Array] Value of subnet ids
  def _process_amq_broker_builder(
    template: nil,
    component_name: nil,
    amq_broker: nil,
    security_groups: nil,
    amq_configuration: nil,
    subnet_ids: nil
  )

    name, definition = amq_broker.first

    Context.component.replace_variables(definition)
    deployment_mode = JsonTools.get(definition, "Properties.DeploymentMode", nil)
    users = JsonTools.get(definition, "Properties.Users", nil)

    template["Resources"][name] = {
      "Type" => "AWS::AmazonMQ::Broker",
      "Properties" => {
        "AutoMinorVersionUpgrade" => JsonTools.get(definition, "Properties.AutoMinorVersionUpgrade", true),
        "DeploymentMode" => JsonTools.get(definition, "Properties.DeploymentMode", nil),
        "SubnetIds" => subnet_ids,
        "EngineType" => JsonTools.get(definition, "Properties.EngineType", "ActiveMQ"),
        "EngineVersion" => JsonTools.get(definition, "Properties.EngineVersion", "5.15.0"),
        "HostInstanceType" => JsonTools.get(definition, "Properties.HostInstanceType", "mq.t2.micro"),
        "PubliclyAccessible" => JsonTools.get(definition, "Properties.PubliclyAccessible", "false"),
        "SecurityGroups" => security_groups,
        "Logs" => {
          "General" => "true",
          "Audit" => "true"
        }
      }
    }

    resource = template["Resources"][name]

    broker_name = JsonTools.get(definition, "Properties.TableName", name)
    sections = Defaults.sections

    # Generate unique MQ Broker name based on component
    fq_name = [
      sections[:ams],
      sections[:qda],
      sections[:as],
      sections[:ase],
      sections[:branch],
      sections[:build],
      component_name,
      broker_name
    ].join('-')

    resource["Properties"]["BrokerName"] = fq_name.gsub(/[^A-Za-z0-9_\-]/, "")[0..50]

    JsonTools.transfer(definition, "Properties.MaintenanceWindowStartTime", resource, nil)

    resource["Properties"]["Configuration"] = {
      "Id" => amq_configuration[:amq_configuration_id],
      "Revision" => amq_configuration[:amq_configuration_revision]
    }

    # Create Parameter for AMQ users
    _process_amq_login(
      template: template,
      resource_name: name,
      component_name: component_name,
      users: users
    )

    # Generate output and put the Broker id in context file

    template["Outputs"]["#{name}BrokerId"] = {
      "Description" => "#{name} Amazon MQ Broker Id",
      "Value" => { "Ref" => name }
    }

    template["Outputs"]["#{name}BrokerArn"] = {
      "Description" => "#{name} Amazon MQ Broker Arn",
      "Value" => { 'Fn::GetAtt' => [name, 'Arn'] }
    }

    template["Outputs"]["#{name}PrimaryBrokerEndpoint"] = {
      "Description" => "#{name} Amazon MQ Primary Endpoint",
      "Value" => { "Fn::Sub" => ["${broker_name}-1.mq.${AWS::Region}.amazonaws.com", { "broker_name" => { "Ref" => "#{name}" } }] }
    }

    template["Outputs"]["#{name}SecondaryBrokerEndpoint"] = {
      "Description" => "#{name} Amazon MQ Secondary Endpoint",
      "Value" => { "Fn::Sub" => ["${broker_name}-2.mq.${AWS::Region}.amazonaws.com", { "broker_name" => { "Ref" => "#{name}" } }] }
    } if deployment_mode == "ACTIVE_STANDBY_MULTI_AZ"
  end

  # Selects the subnet.
  # Amazon MQ Broker supports single subnet value if SINGLE_INSTANCE is built
  # It supports only 2 subnet ids if ACTIVE_STANDBY_MULTI_AZ is built
  # @param deployment_mode [String] The type of deployment
  # @param subnet_alias [String] The subnet alias provided.
  # @return subnet_ids [Array] returns subnet ids
  def _subnet_ids(deployment_mode:, subnet_alias:)
    subnet_id = Context.environment.subnet_ids(subnet_alias)
    subnet_ids = []

    case deployment_mode
    when "SINGLE_INSTANCE"
      subnet_ids << subnet_id[0]
    when "ACTIVE_STANDBY_MULTI_AZ"
      # Only 2 subnet ids can be provided if deployment mode selected is Active Standby.
      # CloudFormation stack will fail if all the 3 subnets are mentioned.
      subnet_ids << subnet_id[0]
      subnet_ids << subnet_id[1]
    else
      raise "Invalid Deployment Mode selected for AMQ #{deployment_mode}"
    end

    return subnet_ids
  end

  # Processes AMQ passwords
  # @param user_definition [Hash] user definition parsed from Component definition file

  def _process_amq_admin_password(user_definition: nil)
    Log.info "Processing AMQ User password"
    Context.component.replace_variables(user_definition)

    encrypted_password = JsonTools.get(user_definition, "Password")

    decrypted_password = AwsHelper.kms_decrypt_data(encrypted_password)

    user_definition['Password'] = decrypted_password
  rescue ActionError => e
    raise "Failed to decrypt the AMQ admin password - #{e}"
  end

  # Updates Cloudfromation template with Amazon MQ user details under Parameter
  # @param template [Hash] CloudFormation template passed in as reference
  # @param resource_name [String] Name of the resource
  # @param component_name [String] Name of the component
  # @param users [Array] User details parsed from component definition file
  def _process_amq_login(
    template: nil,
    resource_name: nil,
    component_name: nil,
    users: nil
  )

    # Update each user details in Template

    resource = template['Resources'][resource_name]

    template['Parameters'] = template['Parameters'] || {}

    raise "AMQ Admin User details not provided in component definition" \
    "Use QCP Console to provide the information" if users.nil? || users.empty?

    users.each do |user|
      para_user_name = "#{resource_name}#{user['Username']}Username"
      para_user_password = "#{resource_name}#{user['Username']}Password"

      Context.component.set_variables(
        component_name,
        para_user_name => user['Username'],
        para_user_password => user['Password']
      )

      template['Parameters'][para_user_name] = {
        'NoEcho' => true,
        'Description' => "AMQ User Name for #{user['Username']}",
        'Type' => 'String'
      }

      template['Parameters'][para_user_password] = {
        'NoEcho' => true,
        'Description' => "AMQ password for #{user['Username']}",
        'Type' => 'String'
      }

      user['Username'] = { 'Ref' => para_user_name }
      user['Password'] = { 'Ref' => para_user_password }
    end
    resource["Properties"]["Users"] = users
  end
end
