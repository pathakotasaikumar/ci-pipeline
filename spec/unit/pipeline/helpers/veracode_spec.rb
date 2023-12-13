require 'pipeline/helpers/veracode'

RSpec.describe Pipeline::Helpers::Veracode do
  context 'initialize' do
    it 'successfully initialises Veracode helper' do
      expect {
        Pipeline::Helpers::Veracode.new(
          branch: 'master',
          scan_dir: '/tmp/dummy-dir',
          config: {
            "crit" => 'Medium',
            "recipients" => ['dummy@example.com'],
            "promote_branch" => 'master',
            "scan_branch" => 'master'
          }
        )
      }.not_to raise_error
    end
  end

  before :context do
    @veracode_run = Pipeline::Helpers::Veracode.new(
      branch: 'master',
      scan_dir: '/tmp/dummy-dir',
      config: {
        "crit" => 'Medium',
        "recipients" => ['dummy@example.com'],
        "promote_branch" => 'master',
        "scan_branch" => ['master']
      }
    )

    @veracode_not_run = Pipeline::Helpers::Veracode.new(
      branch: 'other',
      scan_dir: '/tmp/dummy-dir',
      config: {
        "crit" => 'Medium',
        "recipients" => ['dummy@example.com'],
        "promote_branch" => 'master',
        "scan_branch" => ['master']
      }
    )
  end

  context 'enabled?' do
    it 'successfully returned - enabled? == true' do
      expect(@veracode_run.enabled?).to eq(true)
    end

    it 'successfully returns - enabled? != true' do
      expect(@veracode_not_run.enabled?).to eq(false)
    end
  end

  context 'package' do
    it 'successfully executes pacakge method' do
      allow(Util::Archive).to receive(:tgz!).and_return(true)
      expect(Log).to receive(:info).with(/Created a new Veracode scan artefact:/)
      expect { @veracode_run.package }.not_to raise_error
    end

    it 'fails to execute pacakge method' do
      allow(Util::Archive).to receive(:tgz!).and_raise(IOError)
      expect { @veracode_run.package }.to raise_exception(IOError)
    end
  end

  context 'upload' do
    it 'successfully executes upload method' do
      allow(AwsHelper).to receive(:s3_upload_file).and_return(nil)
      expect(Log).to receive(:info).with(/Uploaded veracode artefact file: /)
      expect { @veracode_run.upload }.not_to raise_error
    end

    it 'fails to execute upload method' do
      allow(AwsHelper).to receive(:s3_upload_file).and_raise(ArgumentError)
      expect { @veracode_run.upload }.to raise_exception(ArgumentError)
    end
  end

  context 'run' do
    it "successfully executes 'run' method" do
      allow(@veracode_run).to receive(:_generate_avos_payload).and_return({})
      allow(@veracode_run).to receive(:_execute_scan).and_return({})
      expect { @veracode_run.run }.not_to raise_error
    end

    it "fails to execute 'run' method 1" do
      allow(@veracode_run).to receive(:_generate_avos_payload).and_raise(StandardError)
      allow(@veracode_run).to receive(:_execute_scan).and_return(nil)
      expect { @veracode_run.run }.to raise_exception(StandardError)
    end

    it "fails to execute 'run' method 2" do
      allow(@veracode_run).to receive(:_generate_avos_payload).and_return(nil)
      allow(@veracode_run).to receive(:_execute_scan).and_raise(StandardError)
      expect { @veracode_run.run }.to raise_exception(StandardError)
    end
  end

  context 'get_config' do
    it 'successfully loads config file' do
      allow(YAML).to receive(:load_file).and_return({
        "veracode" => {
          "crit" => 'Medium',
          "recipients" => ['dummy@example.com'],
          "promote_branch" => 'master',
          "scan_branch" => 'master'
        }
      })
      puts YAML.dump(Pipeline::Helpers::Veracode.load_config('dummy-path'))
      expect(Pipeline::Helpers::Veracode.load_config('dummy-path').fetch('crit')).to eq('Medium')
    end

    it 'fails to load config file' do
      allow(YAML).to receive(:load_file).and_raise(Errno::ENOENT)
      expect(Log).to receive(:error).with(/Unable to load Veracode configuration file: /)
      expect(Pipeline::Helpers::Veracode.load_config('dummy-path')).to eq({})
    end
  end

  context '_execute_scan' do
    it 'successfully executes _execute_scan method' do
      mock_lambda_client = double(Object)
      function_name = 'dummy-function-arn'
      payload = { 'crit' => 'Medium' }
      allow(@veracode_run).to receive(:_lambda_client).and_return(mock_lambda_client)
      allow(mock_lambda_client).to receive(:lambda_invoke).and_return({})
      expect(Log).to receive(:info).with("Successfully triggered Veracode Workflow: #{function_name} with payload #{payload}")
      expect { @veracode_run.send(:_execute_scan, function_name, payload) }.not_to raise_exception
    end

    it 'fails to execute _execute_scan method' do
      mock_lambda_client = double(Object)
      function_name = 'dummy-function-arn'
      payload = { 'crit' => 'Medium' }
      allow(@veracode_run).to receive(:_lambda_client).and_return(mock_lambda_client)
      allow(mock_lambda_client).to receive(:lambda_invoke).and_raise(StandardError)
      expect { @veracode_run.send(:_execute_scan, function_name, payload) }
        .to raise_exception("Failed to trigger Veracode Workflow: #{function_name} with payload #{payload} - StandardError")
    end
  end

  context '_generate_avos_payload' do
    it 'successfully executes _generate_avos_payload method' do
      allow(SecureRandom).to receive(:hex).and_return('abcdef1234567890')
      expected_payload = {
        app_name: "ams01-c031-99",
        artefact: "scan.tar.gz",
        branch: "master",
        bucket: "qcp-veracode-prod",
        crit: "Medium",
        execution_id: "abcdef1234567890",
        path: "ams01/c031/99/master/5",
        promote_branch: "master",
        recipients: ["dummy@example.com"],
        tag: "ams01-c031-99"
      }
      expect(@veracode_run.send(:_generate_avos_payload)).to eq(expected_payload)
    end
  end

  context '_lambda_client' do
    it 'successfully returns a lambda client' do
      allow(Defaults).to receive(:proxy).and_return('dummy_proxy')
      allow(Defaults).to receive(:region).and_return('dummy_region')
      allow(Defaults).to receive(:control_role).and_return('dummy_control_role')
      allow(Defaults).to receive(:proxy).and_return(nil)

      mock_client = double(AwsHelperClass)
      allow(AwsHelperClass).to receive(:new).and_return(mock_client)
      expect { @veracode_run.send :_lambda_client }.not_to raise_exception
    end

    it 'fails to return lambda client' do
      allow(Defaults).to receive(:proxy).and_return('dummy_proxy')
      allow(Defaults).to receive(:region).and_return('dummy_region')
      allow(Defaults).to receive(:control_role).and_return('dummy_control_role')
      allow(Defaults).to receive(:proxy).and_return(nil)

      allow(AwsHelperClass).to receive(:new).and_raise(StandardError)
      expect { @veracode_run.send :_lambda_client }.to raise_exception(StandardError)
    end
  end
end
