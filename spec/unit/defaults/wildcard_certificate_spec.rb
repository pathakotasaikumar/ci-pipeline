require 'defaults/wildcard_certificate'

RSpec.describe Defaults::WildCardCertificate do
  context 'nonp_wildcard_qcpaws_certificate_name' do
    it 'successfully return wildcard_qcpaws_certificate_nonp' do
      allow(Context).to receive_message_chain('environment.variable').with('wildcard_qcpaws_certificate_nonp').and_return('dummy-certificate')
      expect(Defaults.nonp_wildcard_qcpaws_certificate_name).to eq('dummy-certificate')
    end
    it 'test if no values return from wildcard_qcpaws_certificate_nonp' do
      allow(Context).to receive_message_chain('environment.variable').with('wildcard_qcpaws_certificate_nonp').and_raise(RuntimeError, 'cannot fetch value')
      expect {
        Defaults.nonp_wildcard_qcpaws_certificate_name
      }.to raise_exception(RuntimeError, /cannot fetch value/)
    end
  end

  context 'prod_wildcard_qcpaws_certificate_name' do
    it 'successfully returns prod_wildcard_qcpaws_certificate_name' do
      allow(Context).to receive_message_chain('environment.variable').with('wildcard_qcpaws_certificate_prod').and_return('dummy-certificate')
      expect(Defaults.prod_wildcard_qcpaws_certificate_name).to eq('dummy-certificate')
    end
    it 'test if no values return from prod_wildcard_qcpaws_certificate_name' do
      allow(Context).to receive_message_chain('environment.variable').with('wildcard_qcpaws_certificate_prod').and_raise(RuntimeError, 'cannot fetch value')
      expect {
        Defaults.prod_wildcard_qcpaws_certificate_name
      }.to raise_exception(RuntimeError, /cannot fetch value/)
    end
  end

  context 'verify_certificate_alias' do
    it 'successfully returns not nil value' do
      expect(Defaults.verify_certificate_alias(certificateAlias: '@wildcard-qcpaws')).not_to eq(nil)
    end

    it 'successfully returns nil value' do
      expect(Defaults.verify_certificate_alias(certificateAlias: 'wildcard-qcpaws')).to eq(nil)
    end
  end
end
