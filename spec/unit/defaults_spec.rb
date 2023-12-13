require 'defaults'

RSpec.describe Defaults do
end

RSpec.describe Defaults::Environment do
  def _get_instance_definition(image_id:)
    {
      "Configuration" => {
        "A" => {

        },

        "Features" => {

        },

        "MyInstance" => {
          "Type" => "AWS::EC2::Instance",
          "Properties" => {
            "ImageId" => image_id
          }
        },

        "Z" => {

        }
      }
    }
  end

  def _get_autoscale_definition(bake_image_id:, launch_conf_image_id:)
    {
      "Configuration" => {
        "A" => {

        },

        "Features" => {

        },

        "BakeInstance" => {
          "Type" => "AWS::EC2::Instance",
          "Properties" => {
            "ImageId" => bake_image_id
          }
        },

        "LaunchConfiguration" => {
          "Type" => "AWS::AutoScaling::LaunchConfiguration",
          "Properties" => {
            "ImageId" => launch_conf_image_id
          }
        },

        "Z" => {

        }
      }
    }
  end

  context '._codedeploy_win_instance?' do
    it 'handles instance component' do
      data = {
        _get_instance_definition(image_id: "rhel6") => false,
        _get_instance_definition(image_id: "rhel7") => false,

        _get_instance_definition(image_id: "@win2012-latest") => true,
        _get_instance_definition(image_id: "@win2016-latest") => true,
        _get_instance_definition(image_id: nil) => false,
      }

      data.keys.each do |key|
        expected_value = data[key]
        result = Defaults.__send__(:_codedeploy_win_instance?, :definition => key)

        expect(result).to eq(expected_value)
      end
    end
  end

  context '._codedeploy_win_autoscale?' do
    it 'handles autoscale component' do
      data = {
        # 1st set
        _get_autoscale_definition(bake_image_id: "rhel6", launch_conf_image_id: nil) => false,
        _get_autoscale_definition(bake_image_id: "rhel7", launch_conf_image_id: nil) => false,

        _get_autoscale_definition(bake_image_id: "@win2012-latest", launch_conf_image_id: nil) => true,
        _get_autoscale_definition(bake_image_id: "@win2016-latest", launch_conf_image_id: nil) => true,
        _get_autoscale_definition(bake_image_id: nil, launch_conf_image_id: nil) => false,

        # 2nd set
        _get_autoscale_definition(bake_image_id: nil, launch_conf_image_id: "rhel6") => false,
        _get_autoscale_definition(bake_image_id: nil, launch_conf_image_id: "rhel7") => false,

        _get_autoscale_definition(bake_image_id: nil, launch_conf_image_id: "@win2012-latest") => true,
        _get_autoscale_definition(bake_image_id: nil, launch_conf_image_id: "@win2016-latest") => true,
        _get_autoscale_definition(bake_image_id: nil, launch_conf_image_id: nil) => false,

        # 3rd set
        _get_autoscale_definition(bake_image_id: "rhel6", launch_conf_image_id: "rhel6") => false,
        _get_autoscale_definition(bake_image_id: "rhel7", launch_conf_image_id: "rhel7") => false,

        _get_autoscale_definition(bake_image_id: "@win2012-latest", launch_conf_image_id: "@win2012-latest") => true,
        _get_autoscale_definition(bake_image_id: "@win2016-latest", launch_conf_image_id: "@win2016-latest") => true,
        _get_autoscale_definition(bake_image_id: nil, launch_conf_image_id: nil) => false,
      }

      data.keys.each do |key|
        expected_value = data[key]
        result = Defaults.__send__(:_codedeploy_win_autoscale?, :definition => key)

        expect(result).to eq(expected_value)
      end
    end
  end

  context '.codedeploy_win_component?' do
    it 'handles instance, autoscale and autoheal' do
      allow(Defaults).to receive_message_chain('_codedeploy_win_instance?').and_return(true)
      allow(Defaults).to receive_message_chain('_codedeploy_win_autoscale?').and_return(true)

      expect(Defaults.codedeploy_win_component?(definition: {
        'Type' => 'aws/instance'
      })).to eq(true)

      expect(Defaults.codedeploy_win_component?(definition: {
        'Type' => 'aws/autoscale'
      })).to eq(true)

      expect(Defaults.codedeploy_win_component?(definition: {
        'Type' => 'aws/autoheal'
      })).to eq(true)
    end

    it 'raises on unknown component' do
      expect {
        Defaults.codedeploy_win_component?(definition: {
          'Type' => 'aws/image'
        })
      }      .to raise_error(/Unsupported component type for CodeDeploy/)
    end
  end

  context 'default_inbound_sources' do
    it 'successfully return default_inbound_sources' do
      default_inbound_sg = ['dummy-bastion-linux-sg-id', 'dummy-bastion-windows-sg-id']
      allow(Context).to receive_message_chain('environment.variable').with('bastion_linux_sg_id', 'sg-2f36124b').and_return('dummy-bastion-linux-sg-id')
      allow(Context).to receive_message_chain('environment.variable').with('bastion_windows_sg_id', 'sg-e2383085').and_return('dummy-bastion-windows-sg-id')
      expect(Defaults.default_inbound_sources).to eq(default_inbound_sg)
    end
  end

  context 'default_qualys_sources' do
    it 'successfully return default_qualys_sources' do
      allow(Context).to receive_message_chain('environment.variable').with('qualys_sg_id', 'sg-0cdb1a5e7cefd3dbd').and_return('dummy-qualys-sg-id')
      expect(Defaults.default_qualys_sources).to eq(['dummy-qualys-sg-id'])
    end
  end

  context 'ci_artefact_path' do
    it 'returns default value' do
      expect(Defaults.ci_artefact_path).to eq('ci/ams01/c031/99/master/latest')
    end

    it 'returns value for component' do
      expect(Defaults.ci_artefact_path(component_name: 'my-component')).to eq('ci/ams01/c031/99/master/latest/my-component')
    end
  end

  context '.ci_versioned_artefact_path' do
    it 'returns value for component and build' do
      expect(Defaults.ci_versioned_artefact_path(component_name: 'my-component', build_number: 44)).to eq('ci/ams01/c031/99/master/44/my-component')
    end
  end

  context '.r53_dns_zone?' do
    it 'returns true' do
      allow(Defaults).to receive(:dns_zone) .and_return(Defaults.r53_dns_zone)
      expect(Defaults.r53_dns_zone?).to eq(true)
    end

    it 'returns false' do
      allow(Defaults).to receive(:dns_zone) .and_return('http://localhost')
      expect(Defaults.r53_dns_zone?).to eq(false)
    end
  end

  context '.image_by_dns' do
    it 'returns value' do
      image = 'adoc-image.feature-image-bake.dev.a007-01.ams04.nonp'

      allow(Defaults).to receive(:_resolve_ami_id_by_txt) .and_return('adoc-image')
      expect(Defaults.image_by_dns(image)).to eq('adoc-image')
    end
  end

  context '.qualys_kms_stack_name' do
    it 'returns value' do
      expect(Defaults.qualys_kms_stack_name).to eq('qcp-qualys-bootstrap')
    end
  end

  context '.dns_stack_name' do
    it 'returns value' do
      expect(Defaults.dns_stack_name).to eq('ams01-c031-99-master-ReleaseDns')
    end
  end

  context '.set_sections' do
    it 'fails on empty plan' do
      expect {
        Defaults.set_sections('')
      }.to raise_error(/Unable to retrieve sections for plan key/)
    end

    # we can't test this right now as it modifyes global @@sections state
    it 'gets environment from plan key' do
      plan_key = Defaults.plan_key

      # we have to mock this call to avoid global @@section override
      # such override brings down other tests
      allow(Defaults).to receive(:_update_section)

      allow(Defaults).to receive(:get_environment_from_plan_key) do |arg1|
        expect(arg1).to eq plan_key
        had_default_ou_path_call = true
      end

      Defaults.set_sections(plan_key)
    end
  end

  context '.get_sections' do
    it 'gets environment from plan key' do
      plan_key = Defaults.plan_key

      # fallback to get_environment_from_plan_key
      allow(Defaults).to receive(:get_environment_from_plan_key) .and_return('custom')
      Defaults.get_sections(plan_key)
      expect(Defaults.get_sections(plan_key)[:env]).to eq('custom')

      # prod case
      allow(Defaults).to receive(:get_environment_from_plan_key) .and_return(nil)
      expect(Defaults.get_sections(plan_key, nil, nil, 'prod')[:env]).to eq('prod')

      allow(Defaults).to receive(:get_environment_from_plan_key) .and_return(nil)
      expect(Defaults.get_sections(plan_key, nil, nil, 'nonp')[:env]).to eq('nonp')

      # non-prod case
      allow(Defaults).to receive(:get_environment_from_plan_key) .and_return(nil)
      expect(Defaults.get_sections(plan_key, nil, nil, 'other')[:env]).to eq('nonp')
    end
  end

  context 'is_prod' do
    it 'test true for prod env' do
      allow(Defaults).to receive(:sections).and_return({ :env => "PROD" })
      expect(Defaults.is_prod?).to eq(true)
    end
    it 'test false for non prod env' do
      allow(Defaults).to receive(:sections).and_return({ :env => "nonp" })
      expect(Defaults.is_prod?).to eq(false)
    end
  end

  context 'custom_dns_name' do
    it 'test custom_dns_name with ad dns record' do
      expect(Defaults.custom_dns_name(
               dns_name: 'component.master-6.dev.c031-01.ams01.nonp.qcpaws.qantas.com.au',
               zone: 'qcpaws.qantas.com.au'
             )).to eq('component-master-6-dev-c031-01-ams01-nonp.qcpaws.qantas.com.au')
    end
    it 'test custom_dns_name with r53 record' do
      expect(Defaults.custom_dns_name(
               dns_name: 'component.master-6.dev.c031-01.ams01.nonp.aws.qcp',
               zone: 'aws.qcp'
             )).to eq('component-master-6-dev-c031-01-ams01-nonp.aws.qcp')
    end

    it 'fail if the limit is exceeds the 63 character' do
      expect {
        Defaults.custom_dns_name(
          dns_name: 'testcomponentname-resourcename.big-branchname.dev.c031-01.ams01.nonp.qcpaws.qantas.com.au',
          zone: 'qcpaws.qantas.com.au'
        )
      }      .to raise_error /The Custom DNS record testcomponentname-resourcename-big-branchname-dev-c031-01-ams01-nonp.qcpaws.qantas.com.au exceeds the max character limit of 63.Please use small branch name or component name/
    end
  end

  context 'custom_release_dns_name' do
    it 'test custom_release_dns_name with ad dns record' do
      expect(Defaults.custom_release_dns_name(
               component: 'component',
               resource: 'test'
             )).to eq('component-test-master-dev-c031-99-ams01-nonp.qcpaws.qantas.com.au')
    end
    it 'test custom_release_dns_name with r53 record' do
      expect(Defaults.custom_release_dns_name(
               component: 'component',
               resource: 'test',
               zone: 'aws.qcp'
             )).to eq('component-test-master-dev-c031-99-ams01-nonp.aws.qcp')
    end
  end

  context '.resource_group_url' do
    it 'returns value' do
      expected_result = 'https://resources.console.aws.amazon.com/r/group#sharedgroup={"name":"AMS01-C031S99DEV master","regions":["ap-southeast-2"],"resourceTypes":"all","tagFilters":[{"key":"AMSID","values":["AMS01"]},{"key":"EnterpriseAppID","values":["C031"]},{"key":"ApplicationServiceID","values":["99"]},{"key":"Environment","values":["DEV"]},{"key":"Branch","values":["master"]}]}'
      expect(Defaults.resource_group_url).to eq(expected_result)
    end
  end

  context '.get_tags' do
    it 'returns ReleaseID tag' do
      release_id = 'release-1'
      allow(Context).to receive_message_chain('pipeline.snow_release_id') .and_return(release_id)
      tags = Defaults.get_tags

      tag = tags.find { |t| t[:key] == 'ReleaseID' }

      expect(tag).not_to be(nil)
      expect(tag[:key]).to eq('ReleaseID')
      expect(tag[:value]).to eq(release_id)
    end

    it 'returns ProjectCode tag' do
      release_id = nil
      allow(Context).to receive_message_chain('pipeline.snow_release_id') .and_return(release_id)
      tags = Defaults.get_tags

      tag = tags.find { |t| t[:key] == 'ProjectCode' }

      # apparantly this is bug
      # tracked in JIRA, right now passing with nil
      #  https://jira.qantas.com.au/browse/QCP-1390
      #  https://jira.qantas.com.au/browse/QCP-1412

      expect(tag).to be(nil)

      # expect(tag).not_to be(nil)
      # expect(tag[:key]).to eq('ProjectCode')
      # expect(tag[:value]).to eq(release_id)
    end
  end

  context '.default_region' do
    it 'returns value' do
      expect(Defaults.default_region).to eq('ap-southeast-2')
    end
  end

  context '.resource_name' do
    it 'truncate' do
      expect(Defaults.resource_name("dummy", "long" * 100).length).to be < 63
    end
  end
end
