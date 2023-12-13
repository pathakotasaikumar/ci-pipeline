module DbInstanceBuilder
  # Processes db user name and login
  # Ensures 'Parameters' section within giving template, creates parameters w/ NoEcho option
  # and updates 'Ref' for MasterUsername/MasterUserPassword
  # @param template [Hash] Reference to a template hash
  # @param resource_name [Hash] CloudFormation logical resource name
  # @param component_name [String] Name of the calling component
  # @param master_user_name [String] Master User name
  # @param master_user_password [String] Master User password
  def _process_db_login(
    template:,
    resource_name:,
    component_name:,
    master_user_name:,
    master_user_password:
  )
    resource = template['Resources'][resource_name]

    param_master_user_name = "#{resource_name}MasterUsername"
    param_master_user_password = "#{resource_name}MasterUserPassword"

    # Save username and password into the context
    Context.component.set_variables(
      component_name,
      param_master_user_name => master_user_name,
      param_master_user_password => master_user_password
    )

    # adding parameters for MasterUsername/MasterUserPassword properties
    template['Parameters'] = template['Parameters'] || {}

    template['Parameters'][param_master_user_name] = {
      'NoEcho' => true,
      'Description' => 'The database admin account username',
      'Type' => 'String'
    }

    template['Parameters'][param_master_user_password] = {
      'NoEcho' => true,
      'Description' => 'The database admin account password',
      'Type' => 'String'
    }

    # patching resource template with refs
    resource['Properties']['MasterUsername'] = { 'Ref' => param_master_user_name }
    resource['Properties']['MasterUserPassword'] = { 'Ref' => param_master_user_password }
  end

  def _process_db_password(definition:)
    Log.info "Processing the Database Master Password"

    Context.component.replace_variables(definition)

    encrypted_password = JsonTools.get(definition, "Properties.MasterUserPassword")

    decrypted_password = AwsHelper.kms_decrypt_data(encrypted_password)

    definition['Properties']['MasterUserPassword'] = decrypted_password
  rescue ActionError => e
    raise "Failed to process the RDS Database password - #{e}"
  end

  # Switch out old instance classes for current generation
  def _replace_db_instance_class(specified_class)
    if !specified_class
      return specified_class
    end
    instance_class = specified_class.gsub('db.m3.medium', 'db.t3.medium') # There is no db.m5.medium
    instance_class = instance_class.gsub('db.m3', 'db.m5')
    instance_class = instance_class.gsub('db.m4', 'db.m5')
    instance_class = instance_class.gsub('db.r3', 'db.r5')
    instance_class = instance_class.gsub('db.r4', 'db.r5')
    return instance_class
  end
end
