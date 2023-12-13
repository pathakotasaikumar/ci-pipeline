module DbOptionGroupBuilder
  def _process_db_option_group(
    template:,
    component_name:,
    db_option_groups:,
    db_option_groups_deletionpolicy:
  )

    db_option_groups.each do |name, definition|
      new_configs = []
      option_configs = JsonTools.get(definition, 'Properties.OptionConfigurations')
      option_configs.each do |config|
        # replace any context with the vpc sg array with their sg/asir listing
        if config.key? 'VpcSecurityGroupMemberships'
          config['VpcSecurityGroupMemberships'] = Context.component.replace_variables(config['VpcSecurityGroupMemberships'])
        end

        # Any OptionSettings with password in name, we need to force secret manager
        if config.key? 'OptionSettings'
          config['OptionSettings'] = _process_db_option_group_settings(
            template: template,
            component_name: component_name,
            option_name: name,
            settings: config['OptionSettings']
          )
        end

        new_configs << config
      end

      template['Resources'][name] = {
        'Type' => 'AWS::RDS::OptionGroup',
        'DeletionPolicy' => db_option_groups_deletionpolicy,
        'Properties' => {
          'EngineName' => JsonTools.get(definition, 'Properties.EngineName'),
          'MajorEngineVersion' => JsonTools.get(definition, 'Properties.MajorEngineVersion'),
          'OptionGroupDescription' => JsonTools.get(definition, 'Properties.OptionGroupDescription', 'Custom Option Group'),
          'OptionConfigurations' => new_configs,
        }
      }

      template['Outputs']["#{name}Name"] = {
        'Description' => 'DB option group name',
        'Value' => { 'Ref' => name },
      }
    end
  end

  def _process_db_option_group_settings(template:, component_name:, option_name:, settings:)
    settings.inject([]) do |result, setting|
      if setting['Name'].downcase.include? 'password'
        # We have a password settings field, for that we need to rewrite the template
        # Move the variable to a parameter and reference that
        Log.info "Parameterising #{setting['Name']} as a password field"

        # Logical ID can't have non-alphanum
        param_settings_password = "#{option_name}#{setting['Name']}".gsub(/[^0-9A-Za-z]/i, '')

        Context.component.set_variables(
          component_name,
          param_settings_password => setting['Value']
        )

        template['Parameters'] = template['Parameters'] || {}

        template['Parameters'][param_settings_password] = {
          'NoEcho' => true,
          'Description' => 'RDS option group settings password',
          'Type' => 'String'
        }

        setting['Value'] = { 'Ref' => param_settings_password }
      end
      result << setting
      result
    end
  end

  def _process_settings_password(settings_definition:)
    Log.info "Processing the RDS Option Group Settings Password"

    Context.component.replace_variables(settings_definition)

    decrypted_password = AwsHelper.kms_decrypt_data(settings_definition['Value'])
    settings_definition['Value'] = decrypted_password
  rescue ActionError => e
    raise "Failed to process the RDS Option Group Settings password - #{e}"
  end
end
