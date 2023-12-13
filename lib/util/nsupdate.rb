require 'open3'
require 'resolv'
module Util
  module Nsupdate
    extend self

    @@kinit_mutex = Mutex.new

    # Create a QCP (qcpaws.qantas.com.au) DNS record
    # @param dns_name [String] dns name
    # @param target [String] target dns record
    # @param type [String] type of dns record
    # @param ttl [Integer] ttl for dns record
    def create_dns_record(dns_name, target, type, ttl = 60)
      Log.info "Creating DNS record: #{dns_name.inspect} #{type} #{target.inspect}"

      begin
        update_dns_record(dns_name:, action: 'add', target:, type:, ttl:)
        Log.snow "Created DNS record (Name = #{dns_name.inspect};" \
                 " Target = #{target.inspect}; Type = #{type.inspect}; TTL = #{ttl.inspect})"
      rescue StandardError
        Log.snow "ERROR: Failed to create DNS record (Name = #{dns_name.inspect};" \
                 "Target = #{target.inspect}; Type = #{type.inspect}; TTL = #{ttl.inspect})"
        raise
      end
    end

    # Delete a QCP DNS record
    # @param dns_name [String] dns record to be deleted
    def delete_dns_record(dns_name)
      Log.info "Deleting DNS record: #{dns_name.inspect}"

      begin
        update_dns_record(dns_name:, action: 'delete')
        Log.snow "Deleted DNS record (Name = #{dns_name.inspect})"
      rescue StandardError
        Log.snow "ERROR: Failed to delete DNS record (Name = #{dns_name.inspect})"
        raise
      end
    end

    # Perform an update of a QCP DNS record
    # @param (see Defaults#create_dns_record)
    def update_dns_record(dns_name: nil, action: nil, target: '', type: '', ttl: '')
      if dns_name.nil? or dns_name.empty?
        raise ArgumentError,
              "Expecting DNS name for parameter 'dns_name', but received an empty string"
      end
      if action.nil? or action.empty?
        raise ArgumentError,
              "Expecting DNS action for parameter 'action', but received an empty string"
      end

      zone = Defaults.send(:ad_zone_dns)
      unless dns_name.end_with? zone
        raise ArgumentError,
              "Unsupported DNS zone in #{dns_name.inspect}, expecting #{zone.inspect}"
      end

      ad_dcs = Defaults.send(:ad_domain_dc_list)
      keytab_path = Defaults.send(:keytab_path)
      ad_principle = Defaults.send(:ad_principle)

      kinit_cmd = "kinit -F -k -t \"#{keytab_path}\" #{ad_principle}@#{zone.upcase}"

      # Call out to NS update leveraging GSS-TSIG with the instance Kerberos backend
      nsupdate_cmd = 'nsupdate -g'

      @@kinit_mutex.synchronize do
        # Initialise Kerberos token
        begin
          run_command('kinit', kinit_cmd)
        rescue StandardError => e
          raise "Unable to execute command '#{kinit_cmd}' - #{e}"
        end

        failed = []
        ad_dcs.each do |dc|
          nsupdate_payload = [
            "server #{dc}.#{zone}\n",
            "zone #{zone}\n",
            "update #{action} #{dns_name} #{ttl} #{type} #{target}\n",
            "send\n",
            "quit\n"
          ].join
          # Execute DNS updates

          exit_code = nil

          # nsupdate has been sporadically failing to update DNS records
          # so we try up to 5 times to update the record.
          5.times do |i|
            exit_code, stdout, stderr = run_command('nsupdate', nsupdate_cmd, nsupdate_payload)
            if exit_code != 0 && i != 4
              attempt = i + 1
              duration = 2**attempt
              Log.warn "Attempt #{attempt}/5 of nsupdate on server #{dc} failed. Retrying in #{duration} seconds."
              sleep duration

              # Renew the TGT if it has been revoked for some reason
              # https://learn.microsoft.com/en-us/windows/security/threat-protection/auditing/event-4768
              # https://www.ietf.org/proceedings/49/I-D/draft-ietf-cat-kerberos-pk-cross-07.txt
              # Since the remote KDC may change its PKCROSS key (referred to in
              # Section 5.2) while there are PKCROSS tickets still active, it SHOULD
              # cache the old PKCROSS keys until the last issued PKCROSS ticket
              # expires.  Otherwise, the remote KDC will respond to a client with a
              # KRB-ERROR message of type KDC_ERR_TGT_REVOKED.
              revoked_error = 'TGT has been revoked'
              if stdout.include?(revoked_error) || stderr.include?(revoked_error)
                Log.info 'Kerberos TGT was revoked. Attempting to renew.'
                run_command('kinit', kinit_cmd)
              end
              next
            end
            break
          end

          next if exit_code.zero?

          failed << dc
          Log.error "Unable to run nsupdate on server: #{dc}"
          raise "Unable to update minimum number of DNS servers in set. Failed DCs: #{failed}" if failed.size > 1
        end
      end
    end

    # Executes local shell command
    # @param name [String] name for the command
    # @param command [String] command and parameters for execution
    # @param stdin [String] STDIN to be used with command
    def run_command(name, command, stdin = nil)
      Log.debug "#{name} command: #{command} stdin: #{stdin}"

      cmd_stdout, cmd_stderr, status = Open3.capture3(command, stdin_data: stdin)
      Log.debug("#{name} command output (STDOUT): #{cmd_stdout}")
      if status.exitstatus != 0
        Log.error "Error when executing #{name} command - #{cmd_stderr}" \
                  "exit status: #{status.exitstatus}"
      end
      [status.exitstatus, cmd_stdout, cmd_stderr]
    end
  end
end
