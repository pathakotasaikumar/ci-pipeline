$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib/util"))
require 'nsupdate'

RSpec.describe Util::Nsupdate do
  before(:context) do
  end

  context '.create_dns_record' do
    it 'raises exception on failure' do
      allow(Util::Nsupdate).to receive(:update_dns_record).and_raise('error1')

      allow(Log).to receive(:debug)
      allow(Log).to receive(:snow)

      expect {
        Util::Nsupdate.create_dns_record(
          'my-dns',
          'my-target',
          'my-type'
        )
      }.to raise_error(/error1/)
    end

    it 'creates dns record' do
      allow(Util::Nsupdate).to receive(:update_dns_record)

      allow(Log).to receive(:debug)
      allow(Log).to receive(:snow)

      expect {
        Util::Nsupdate.create_dns_record(
          'my-dns',
          'my-target',
          'my-type'
        )
      }.not_to raise_error
    end
  end

  context '.delete_dns_record' do
    it 'raises exception on failure' do
      allow(Util::Nsupdate).to receive(:update_dns_record).and_raise('error1')

      allow(Log).to receive(:debug)
      allow(Log).to receive(:snow)

      expect {
        Util::Nsupdate.delete_dns_record(
          'my-dns-name'
        )
      }.to raise_error(/error1/)
    end

    it 'deletes dns record' do
      allow(Util::Nsupdate).to receive(:update_dns_record)

      allow(Log).to receive(:debug)
      allow(Log).to receive(:snow)

      expect {
        Util::Nsupdate.delete_dns_record(
          'my-dns-name'
        )
      }.not_to raise_error
    end
  end

  context '.update_dns_record' do
    it 'expects dns_name param' do
      expect {
        Util::Nsupdate.update_dns_record(
          dns_name: nil,
        )
      }.to raise_error(ArgumentError, /Expecting DNS name for parameter 'dns_name', but received an empty string/)
    end

    it 'expects action param' do
      expect {
        Util::Nsupdate.update_dns_record(
          dns_name: 'dns',
          action: nil
        )
      }.to raise_error(ArgumentError, /Expecting DNS action for parameter 'action', but received an empty string/)
    end

    it 'expects zone_dns' do
      allow(Defaults).to receive(:ad_zone_dns).and_return(nil)

      expect {
        Util::Nsupdate.update_dns_record(
          dns_name: 'dns',
          action: 'action'
        )
      }.to raise_error(TypeError, /no implicit conversion of nil into String/)
    end

    it 'raises on failed kinit call' do
      allow(Defaults).to receive(:ad_zone_dns).and_return('localhost.local')

      allow(Defaults).to receive(:ad_domain_dc_list).and_return([])
      allow(Defaults).to receive(:keytab_path).and_return('keytab')
      allow(Defaults).to receive(:ad_principle).and_return('ad_pronciple')

      kinit_cmd = 'kinit -F -k -t "keytab" ad_pronciple@LOCALHOST.LOCAL'
      allow(Util::Nsupdate).to receive(:run_command).with('kinit', kinit_cmd).and_raise("Cannot run kinit")

      expect {
        Util::Nsupdate.update_dns_record(
          dns_name: '42.localhost.local',
          action: 'action'
        )
      }.to raise_error(/Cannot run kinit/)
    end

    it 'raises on failed nsupdate call' do
      allow(Defaults).to receive(:ad_zone_dns).and_return('localhost.local')

      allow(Defaults).to receive(:ad_domain_dc_list).and_return(['dc1', 'dc2'])
      allow(Defaults).to receive(:keytab_path).and_return('keytab')
      allow(Defaults).to receive(:ad_principle).and_return('ad_pronciple')

      kinit_cmd = 'kinit -F -k -t "keytab" ad_pronciple@LOCALHOST.LOCAL'
      allow(Util::Nsupdate).to receive(:run_command).with('kinit', kinit_cmd)

      nsupdate_cmd = 'nsupdate -g'
      nsupdate_payload = [
        'server dc1.localhost.local',
        'zone localhost.local',
        'update action 42.localhost.local',
        'send',
        'quit'
      ].join("\n")

      allow(Util::Nsupdate).to receive(:run_command)
        .with('nsupdate', anything, anything)
        .and_raise("Cannot run nsupdate")

      expect {
        Util::Nsupdate.update_dns_record(
          dns_name: '42.localhost.local',
          action: 'action'
        )
      }.to raise_error(/Cannot run nsupdate/)
    end
  end

  context '.run_command' do
    it 'returns cmd exit code 0' do
      name = ""
      cmd = 'echo 1'
      stdin = nil

      result, = Util::Nsupdate.run_command(name, cmd, stdin)

      expect(result).to eq(0)
    end

    it 'returns cmd exit code != 0' do
      name = ""
      cmd = 'echo 1; exit -1'
      stdin = nil

      result = Util::Nsupdate.run_command(name, cmd, stdin)

      expect(result).not_to eq(0)
    end

    it 'redirects to giving stdin' do
      name = ""
      cmd = "echo"
      stdin = 'my-value-1'

      result, = Util::Nsupdate.run_command(name, cmd, stdin)

      expect(result).to eq(0)
    end
  end
end
