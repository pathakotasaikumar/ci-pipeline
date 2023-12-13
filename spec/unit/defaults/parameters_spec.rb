require "#{BASE_DIR}/lib/defaults/parameters"

RSpec.describe 'Parameters' do
  context '.ad_join_user' do
    it 'returns value' do
      allow(Context).to receive_message_chain('environment.variable').with('ad_join_user', nil).and_return('dummy-test-user')
      expect(Defaults.ad_join_user).to eq('dummy-test-user')
    end
  end

  context '.ad_join_password' do
    it 'returns value' do
      allow(Context).to receive_message_chain('environment.variable').with('ad_join_password', nil).and_return('dummy-test-password')
      expect(Defaults.ad_join_password).to eq('dummy-test-password')
    end
  end

  context '.soe_ami_id' do
    it 'raises exception on empty soe_ami_ids var' do
      expect { Defaults::Parameters.soe_ami_id('test') }.to raise_exception(/Cannot find SOE AMI id/)
    end

    it 'successfully finds amazon-july soe' do
      allow(Defaults).to receive(:soe_ami_ids).and_return({ 'amazon-july' => 'ami-01234567', '@amazon-latest' => 'amazon-july' })
      expect(Defaults::Parameters.soe_ami_id('amazon-july')).to eq('ami-01234567')
    end

    it 'successfully finds amazon-latest soe by alias' do
      allow(Defaults).to receive(:soe_ami_ids).and_return({ 'amazon-july' => 'ami-01234567', 'amazon-latest' => '@amazon-july' })
      expect(Defaults::Parameters.soe_ami_id('amazon-latest')).to eq('ami-01234567')
    end

    it 'lookup URL SOE with image_by_dns' do
      allow(Defaults).to receive(:image_by_dns).and_return('ami-200500')
      allow(Defaults).to receive(:soe_ami_ids).and_return({ 'amazon-july' => 'image.master.dev.c031-89.ams01.nonp.qcpaws.qantas.com.au', 'amazon-latest' => '@amazon-july' })
      allow(Defaults).to receive(:dns_zone).and_return('aws.qcp')

      result = Defaults::Parameters.soe_ami_id('amazon-july')
      expect(result).to eq('ami-200500')
    end
  end

  context '.pipeline_parameter_prefix' do
    it 'returns value' do
      expect(Defaults::Parameters.pipeline_parameter_prefix).to eq('/pipeline')
    end
  end

  context '.pipeline_build_metadata_dynamodb_table_name' do
    it 'returns value' do
      allow(Context).to receive_message_chain('environment.variable').with('pipeline_build_metadata_table_name').and_return('dummy-table-name')
      expect(Defaults.pipeline_build_metadata_dynamodb_table_name).to eq('dummy-table-name')
    end

    it 'fails to return value' do
      allow(Context).to receive_message_chain('environment.variable').with('pipeline_build_metadata_table_name').and_raise('cannot return value')
      expect {
        Defaults.pipeline_build_metadata_dynamodb_table_name
      }.to raise_exception(RuntimeError, 'cannot return value')
    end
  end

  context '.aws_proxy' do
    it 'successfully return value' do
      allow(Context).to receive_message_chain('environment.variable').with('aws_proxy', nil).and_return('dummy-proxy')
      expect(Defaults.aws_proxy).to eq('dummy-proxy')
    end

    it 'successfully return default value' do
      expect(Defaults.aws_proxy).to eq('http://proxy.qcpaws.qantas.com.au:3128')
    end
  end

  context '.pipeline_validation_mode' do
    it 'successfully return value' do
      expect(Defaults.pipeline_validation_mode).to eq('enforce')
    end

    it 'successfully return custom value' do
      allow(Context).to receive_message_chain('environment.variable').with('validation_mode', anything).and_return('11')
      expect(Defaults.pipeline_validation_mode).to eq('11')
    end
  end

  context '.secrets_bucket_name' do
    it 'return default value' do
      expect(Defaults.secrets_bucket_name).to eq('qcp-secret-management-bucket')
    end

    it 'successfully return custom value' do
      allow(Context).to receive_message_chain('environment.variable').with('secrets_bucket_name', anything).and_return('qcp-secret-bucket')
      expect(Defaults.secrets_bucket_name).to eq('qcp-secret-bucket')
    end
  end

  context '.secrets_file_location_path' do
    it 'return default value' do
      expect(Defaults.secrets_file_location_path).to eq('platform-secrets-storage/secrets.json')
    end

    it 'successfully return custom value' do
      allow(Context).to receive_message_chain('environment.variable').with('secrets_file_location_path', anything).and_return('platform-custom-storage/secrets.json')
      expect(Defaults.secrets_file_location_path).to eq('platform-custom-storage/secrets.json')
    end
  end

  context '.pipeline_use_custom_validation?' do
    it 'successfully return value' do
      allow(Context).to receive_message_chain('environment.variable').with('pipeline_custom_validation', nil).and_return(nil)
      expect(Defaults.pipeline_use_custom_validation?).to eq(false)
    end

    it 'successfully return value (empty string)' do
      allow(Context).to receive_message_chain('environment.variable').with('pipeline_custom_validation', nil).and_return("")
      expect(Defaults.pipeline_use_custom_validation?).to eq(false)
    end

    it 'successfully return custom value' do
      allow(Context).to receive_message_chain('environment.variable').with('pipeline_custom_validation', nil).and_return('11')
      expect(Defaults.pipeline_use_custom_validation?).to eq(true)
    end
  end

  context '.argv' do
    it 'sets argv' do
      data = [1, 2, 3]

      Defaults.set_argv(data)
      result = Defaults.argv

      expect(result).to eq(data)
    end
  end

  context '.pipeline_task' do
    it 'sets pipeline_task' do
      data = "my-task"

      Defaults.set_pipeline_task(data)
      result = Defaults.pipeline_task

      expect(result).to eq(data)
    end

    it 'is_ci_pipeline_task? returns value' do
      Defaults.set_pipeline_task('upload')
      expect(Defaults.is_ci_pipeline_task?).to eq(true)

      Defaults.set_pipeline_task('other')
      expect(Defaults.is_ci_pipeline_task?).to eq(false)

      Defaults.set_pipeline_task(nil)
      expect {
        Defaults.is_ci_pipeline_task?
      }.to raise_error(/variable is not set, call Defaults.set_pipeline_task/)
    end

    it 'is_cd_pipeline_task? returns value' do
      Defaults.set_pipeline_task('deploy')
      expect(Defaults.is_cd_pipeline_task?).to eq(true)

      Defaults.set_pipeline_task('release')
      expect(Defaults.is_cd_pipeline_task?).to eq(true)

      Defaults.set_pipeline_task('teardown')
      expect(Defaults.is_cd_pipeline_task?).to eq(true)

      Defaults.set_pipeline_task('other')
      expect(Defaults.is_cd_pipeline_task?).to eq(false)

      Defaults.set_pipeline_task(nil)

      expect {
        Defaults.is_cd_pipeline_task?
      }.to raise_error(/variable is not set, call Defaults.set_pipeline_task/)
    end
  end

  context '.parse_argv' do
    it 'errors on nil task' do
      expect(Log).to receive(:error).with(/Cannot find known pipeline task/)
      Defaults.parse_argv
    end

    it 'errors on unknown task' do
      expect(Log).to receive(:error).with(/Cannot find known pipeline task/)

      Defaults.set_argv(['some-task'])
      Defaults.parse_argv
    end

    it 'finds known task' do
      known_tasks = [
        'upload', 'upload:validate',
        'deploy', 'release', 'teardown'
      ]

      known_tasks.each do |task_name|
        Defaults.set_argv([task_name])

        expect(Log).to receive(:debug).with(/Parsing ARGV values/)
        expect(Log).to receive(:debug).with(/Detected pipeline task/)
        expect(Log).to receive(:debug).with(/Running pipeline task/)

        Defaults.parse_argv
      end
    end
  end

  context 'permission_boundary_policy' do
    it 'successfully return permission_boundary_policy' do
      allow(Context).to receive_message_chain('environment.variable').with('permission_boundary_policy', 'PermissionBoundaryPolicy').and_return('dummy-perms-boundary-policy')
      expect(Defaults.permission_boundary_policy).to eq('dummy-perms-boundary-policy')
    end

    it 'fails to return permission_boundary_policy' do
      allow(Context).to receive_message_chain('environment.variable').with('permission_boundary_policy', 'PermissionBoundaryPolicy').and_return('PermissionBoundaryPolicy')
      expect(Defaults.permission_boundary_policy).to eq('PermissionBoundaryPolicy')
    end
  end
end
