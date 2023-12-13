require 'defaults/qualys'

RSpec.describe Defaults::Nsupdate do
  context 'ad_domain_dc_list' do
    it 'successfully return ad_domain_dc_list ' do
      allow(Context).to receive_message_chain('environment.variable').and_return(%w(awssyddc09 awssyddc12))
      expect(Defaults.send(:ad_domain_dc_list)).to eq(%w(awssyddc09 awssyddc12))
    end

    it 'default  return ad_domain_dc_list key' do
      allow(Context).to receive_message_chain('environment.variable').and_return(%w(awssyddc07 awssyddc08 awssyddc09 awssyddc10 awssyddc11 awssyddc12))
      expect(Defaults.send(:ad_domain_dc_list)).to eq(%w(awssyddc07 awssyddc08 awssyddc09 awssyddc10 awssyddc11 awssyddc12))
    end
  end

  it 'successfully return keytab_path ' do
    expect(Defaults.send(:keytab_path)).to eq('/data/bambooagent/dns-qcpaws.keytab')
  end

  it 'successfully return ad_principle ' do
    expect(Defaults.send(:ad_principle)).to eq('SVC_Atlassian')
  end

  it 'successfully return ad_zone_dns ' do
    expect(Defaults.send(:ad_zone_dns)).to eq('qcpaws.qantas.com.au')
  end
end
