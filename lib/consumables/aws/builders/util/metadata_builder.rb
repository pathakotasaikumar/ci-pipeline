class MetadataBuilder
  def self.build(
    user_metadata: nil,

    pre_prepare: nil,
    post_prepare: nil,

    pre_deploy: nil,
    post_deploy: nil,

    auth: nil
  )

    user_metadata ||= {}

    pre_prepare ||= {}
    post_prepare ||= {}

    pre_deploy ||= {}
    post_deploy ||= {}

    auth ||= {}

    user_metadata_cfninit = user_metadata['AWS::CloudFormation::Init'] || {}
    user_metadata_auth = user_metadata['AWS::CloudFormation::Authentication'] || {}

    if user_metadata_cfninit.has_key? 'configSets' and user_metadata_cfninit.has_key? 'config'
      raise "Cannot specify both 'configSets' and 'config'"
    end

    if user_metadata_cfninit.has_key? 'configSets'
      # The user has specified configSets
      raise "configSets must be a Hash" unless user_metadata_cfninit['configSets'].is_a? Hash
      raise "configSets must be either 'Prepare' or 'Deploy'" unless user_metadata_cfninit['configSets'].keys.all? { |key| key == 'Prepare' or key == 'Deploy' }

      user_prepare_config_set = user_metadata_cfninit['configSets']['Prepare'] || []
      user_deploy_config_set = user_metadata_cfninit['configSets']['Deploy'] || []
    elsif user_metadata_cfninit.has_key? 'config'
      # The user has specified the config key - put all of their blocks into the 'Deploy' config set
      raise "config must be a Hash" unless user_metadata_cfninit['config'].is_a? Hash

      user_prepare_config_set = []
      user_deploy_config_set = ["config"]
    else
      # The user hasn't specified 'configSets' or 'config' - continue with only pipeline config
      user_prepare_config_set = []
      user_deploy_config_set = []
    end

    # Start creating our configSets
    cfn_init = {}
    cfn_init['configSets'] = {
      'Prepare' => [],
      'Deploy' => []
    }

    # Configure the Pre config set
    if !pre_prepare.empty?
      cfn_init['configSets']['Prepare'] << "PrePrepare"
      cfn_init['PrePrepare'] = pre_prepare
    end

    user_prepare_config_set.each do |key|
      raise "Cannot find referenced config key #{key.inspect} in metadata AWS::CloudFormation::Init" unless user_metadata_cfninit.has_key? key

      cfn_init['configSets']['Prepare'] << "User#{key}"
      cfn_init["User#{key}"] = user_metadata_cfninit[key]
    end

    if !post_prepare.empty?
      cfn_init['configSets']['Prepare'] << "PostPrepare"
      cfn_init['PostPrepare'] = post_prepare
    end

    # Configure the Deploy config set
    if !pre_deploy.empty?
      cfn_init['configSets']['Deploy'] << "PreDeploy"
      cfn_init['PreDeploy'] = pre_deploy
    end

    user_deploy_config_set.each do |key|
      raise "Cannot find referenced config key #{key.inspect} in metadata AWS::CloudFormation::Init" unless user_metadata_cfninit.has_key? key

      cfn_init['configSets']['Deploy'] << "User#{key}"
      cfn_init["User#{key}"] = user_metadata_cfninit[key]
    end

    if !post_deploy.empty?
      cfn_init['configSets']['Deploy'] << "PostDeploy"
      cfn_init['PostDeploy'] = post_deploy
    end

    # Configure Auth
    cfn_auth = user_metadata_auth.merge(auth)

    # Create the metadata block
    metadata = {}
    metadata['AWS::CloudFormation::Init'] = cfn_init
    metadata['AWS::CloudFormation::Authentication'] = cfn_auth unless cfn_auth.empty?

    return metadata
  end
end
