require 'defaults/veracode'

RSpec.describe Defaults::Veracode do
  context 'avos_release_arn' do
    it 'successfully return AVOS release arn' do
      allow(Context).to receive_message_chain('environment.variable')
        .with('avos_release_arn', nil)
        .and_return('dummy-avos-release-arn')
      expect(Defaults.avos_release_arn).to eq('dummy-avos-release-arn')
    end

    it 'fails to return AVOS release arn' do
      allow(Context).to receive_message_chain('environment.variable')
        .with('avos_release_arn', nil)
        .and_return(nil)
      expect(Defaults.avos_release_arn).to eq(nil)
    end
  end

  context 'avos_invocation_role' do
    it 'successfully return AVOS invocation role' do
      allow(Context).to receive_message_chain('environment.variable')
        .with('avos_invocation_role', nil)
        .and_return('dummy-role')
      expect(Defaults.avos_invocation_role).to eq('dummy-role')
    end

    it 'fails to return AVOS invocation role' do
      allow(Context).to receive_message_chain('environment.variable')
        .with('avos_invocation_role', nil)
        .and_return(nil)
      expect(Defaults.avos_invocation_role).to eq(nil)
    end
  end

  context 'veracode_bucket_name' do
    it 'successfully return veracode custom bucket' do
      allow(Context).to receive_message_chain('environment.variable').and_return('dummy-bucket-name')
      expect(Defaults.avos_bucket_name).to eq('dummy-bucket-name')
    end

    it 'successfully returns veracode default bucket' do
      allow(Context).to receive_message_chain('environment.variable').and_return('qcp-veracode-prod')
      expect(Defaults.avos_bucket_name).to eq('qcp-veracode-prod')
    end
  end

  context 'veracode_artefact_prefix' do
    it 'successfully return veracode artefact prefix' do
      expect(Defaults.avos_artefact_prefix).to eq('ams01/c031/99/master/5')
    end
  end

  context 'veracode_app_name' do
    it 'successfully return veracode_app_name' do
      expect(Defaults.avos_app_name).to eq('ams01-c031-99')
    end
  end
end
