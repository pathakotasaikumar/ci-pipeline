module AmqBrokerSpec
  def _validate_amq_login(template, expected_template)
    dst_parameters = expected_template['Parameters']

    template['Resources'].each do |key, src_resource|
      dst_resource = expected_template['Resources'][key]

      src_props = src_resource['Properties']['Users']
      dst_props = dst_resource['Properties']['Users']

      username_prop = key + 'TestUserUsername'
      userpass_prop = key + 'TestUserPassword'

      src_props.each do |user_details|
        next unless user_details.key? 'Username'

        expect(dst_props[0]['Username']).to be_a(Hash)
        expect(dst_props[0]['Password']).to be_a(Hash)
        expect(dst_props[0]['Username']['Ref']).to be_a(String)
        expect(dst_props[0]['Username']['Ref']).to eq(username_prop)
        expect(dst_props[0]['Password']['Ref']).to be_a(String)
        expect(dst_props[0]['Password']['Ref']).to eq(userpass_prop)

        # expect(dst_parameters[username_prop]).to be_a(Hash)
        # expect(dst_parameters[userpass_prop]).to be_a(Hash)
        #
      end

      expect(dst_parameters[username_prop]).to be_a(Hash)
      expect(dst_parameters[userpass_prop]).to be_a(Hash)

      # NoEcho set to true
      expect(dst_parameters[username_prop]['NoEcho'])
      expect(dst_parameters[userpass_prop]['NoEcho'])
    end
  end
end
