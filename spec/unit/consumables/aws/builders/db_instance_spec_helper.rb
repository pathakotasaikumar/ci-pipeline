module DbInstanceSpecHelper
  # Validate Parameters section for MasterUsername/MasterUserPassword properties
  # Checks if parames are present and NoEcho set to 'true'
  # @param [Hash] template
  # @param [Hash] expected_template
  def _validate_db_login(template, expected_template)
    dst_parameters = expected_template['Parameters']

    template['Resources'].each do |key, src_resource|
      dst_resource = expected_template['Resources'][key]

      src_props = src_resource['Properties']
      dst_props = dst_resource['Properties']

      username_prop = key + 'MasterUsername'
      userpass_prop = key + 'MasterUserPassword'

      next unless src_props.key? 'MasterUsername'

      # both are hashes
      expect(dst_props['MasterUsername']).to be_a(Hash)
      expect(dst_props['MasterUserPassword']).to be_a(Hash)

      # both are refs to params
      expect(dst_props['MasterUsername']['Ref']).to be_a(String)
      expect(dst_props['MasterUsername']['Ref']).to eq(username_prop)
      expect(dst_props['MasterUserPassword']['Ref']).to be_a(String)
      expect(dst_props['MasterUserPassword']['Ref']).to eq(userpass_prop)

      # exists in parameters section
      expect(dst_parameters[username_prop]).to be_a(Hash)
      expect(dst_parameters[userpass_prop]).to be_a(Hash)

      # NoEcho set to true
      expect(dst_parameters[username_prop]['NoEcho'])
      expect(dst_parameters[userpass_prop]['NoEcho'])
    end
  end
end
