$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws")
require 'aws_codedeploy'
# require 'builders/instance_builder'

RSpec.describe AwsCodeDeploy do
  # include InstanceBuilder

  before(:context) do
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))['UnitTest']
    @component_name = @test_data['Input']['ComponentName']
  end

  context '.initialize' do
    it 'initialize without error' do
      AwsCodeDeploy.new(@component_name, @test_data['Input']['Initialize']['Valid'])
    end

    it 'initialize with DataDog feature' do
      AwsCodeDeploy.new(@component_name, @test_data['Input']['Initialize']['ValidDatadog'])
    end

    it 'throws exception if multiple instances are found in definition' do
      expect {
        AwsCodeDeploy.new(@component_name, @test_data['Input']['Initialize']['Invalid']['MutlipleInstances'])
      }.to raise_error(RuntimeError, /#{@test_data['Output']['Initialize']['Invalid']['MutlipleInstances']}/)
    end

    it 'throws exception on null type' do
      expect {
        AwsCodeDeploy.new(@component_name, @test_data['Input']['Initialize']['Invalid']['EmptyType'])
      }.to raise_error(/Must specify a type for resource/)
    end

    it 'throws exception on unsupported type' do
      expect {
        AwsCodeDeploy.new(@component_name, @test_data['Input']['Initialize']['Invalid']['NotSupportedType'])
      }.to raise_error(/is not supported by this component/)
    end
  end

  context '.security_items' do
    it 'returns security items' do
      component = AwsCodeDeploy.new(@component_name, @test_data['Input']['Initialize']['Valid'])
      result = component.security_items

      expect(result.class).to eq(Array)
      expect(result.count).to eq(1)

      item = result[0]

      expect(item["Name"]).to eq('CodeDeployExecutionRole')
      expect(item["Type"]).to eq('Role')
      expect(item["Component"]).to eq('TestComponent')
      expect(item["Service"]).to eq('codedeploy.ap-southeast-2.amazonaws.com')
    end
  end

  context '.security_rules' do
    it 'returns security rules' do
      component = AwsCodeDeploy.new(@component_name, @test_data['Input']['Initialize']['Valid'])

      allow(Context).to receive_message_chain('component.role_arn').and_return("arn:aws:iam::569253263856:role/ams03-p106-01-dev-QCP-989-25-rhel7-Se-InstanceRole-2LJOU2I0U64V")

      # more limited copy of built-in AWSCodeDeployRole
      # arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole
      # in-place deployment only, we removed all terminate-delete/elasticloadbalancing permissions
      # check aws_codedeploy.rb for more details

      expect(component.security_rules[0]).to eq IamSecurityRule.new(
        roles: @component_name + '.CodeDeployExecutionRole',
        actions: [
          "autoscaling:CompleteLifecycleAction",
          "autoscaling:DeleteLifecycleHook",
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeLifecycleHooks",
          "autoscaling:PutLifecycleHook",
          "autoscaling:RecordLifecycleActionHeartbeat",
          "autoscaling:CreateAutoScalingGroup",
          "autoscaling:UpdateAutoScalingGroup",
          "autoscaling:EnableMetricsCollection",
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribePolicies",
          "autoscaling:DescribeScheduledActions",
          "autoscaling:DescribeNotificationConfigurations",
          "autoscaling:DescribeLifecycleHooks",
          "autoscaling:SuspendProcesses",
          "autoscaling:ResumeProcesses",
          "autoscaling:AttachLoadBalancers",
          "autoscaling:PutScalingPolicy",
          "autoscaling:PutScheduledUpdateGroupAction",
          "autoscaling:PutNotificationConfiguration",
          "autoscaling:PutLifecycleHook",
          "autoscaling:DescribeScalingActivities",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus",
          "tag:GetTags",
          "tag:GetResources",
          "sns:Publish",
          "cloudwatch:DescribeAlarms",
          "cloudwatch:PutMetricAlarm",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeInstanceHealth",
          "elasticloadbalancing:RegisterInstancesWithLoadBalancer",
          "elasticloadbalancing:DeregisterInstancesFromLoadBalancer",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:RegisterTargets",
          "elasticloadbalancing:DeregisterTargets"
        ],

        resources: '*'
      )
    end
  end

  context '.deploy' do
    it 'deploys stack' do
      component = AwsCodeDeploy.new(@component_name, @test_data['Input']['Initialize']['Valid'])

      allow(component).to receive(:_full_template)
      allow(AwsHelper).to receive(:cfn_create_stack) .and_return({})

      allow(Context).to receive_message_chain('component.set_variables')

      expect { component.deploy }.not_to raise_exception
    end

    it 'raises on failed deployment' do
      component = AwsCodeDeploy.new(@component_name, @test_data['Input']['Initialize']['Valid'])

      allow(Defaults).to receive(:component_stack_name).and_raise('Cannot provision')

      expect { component.deploy }.to raise_exception(/Cannot provision/)
    end
  end

  context '.release' do
    it 'releases stack' do
      component = AwsCodeDeploy.new(@component_name, @test_data['Input']['Initialize']['Valid'])

      allow(AwsHelper).to receive(:cfn_create_stack) .and_return({})

      allow(Context).to receive_message_chain('component.set_variables')
      allow(Context).to receive_message_chain("component.replace_variables")
      allow(Context).to receive_message_chain('s3.artefact_bucket_name')

      allow(Context).to receive_message_chain('component.build_number')
      allow(Context).to receive_message_chain('component.variable')
      allow(Context).to receive_message_chain('component.role_arn')
      allow(Context).to receive_message_chain('component.stack_id')

      expect { component.release }.not_to raise_exception
    end
  end

  context '.teardown' do
    it 'deletes stack' do
      component = AwsCodeDeploy.new(@component_name, @test_data['Input']['Initialize']['Valid'])

      allow(AwsHelper).to receive(:cfn_delete_stack)
      allow(Context).to receive_message_chain('component.variable')
      allow(Context).to receive_message_chain('component.stack_id')

      expect { component.teardown }.not_to raise_exception
    end

    it 'raises on failed stack deletion' do
      component = AwsCodeDeploy.new(@component_name, @test_data['Input']['Initialize']['Valid'])

      allow(Context).to receive_message_chain('component.stack_id').and_return('1')
      allow(AwsHelper).to receive(:cfn_delete_stack).and_raise('Cannot delete stack')

      allow(Context).to receive_message_chain('component.variable')
      allow(Context).to receive_message_chain('component.stack_id') .and_return(1)

      expect { component.teardown }.to raise_exception(/Cannot delete stack/)
    end
  end

  context '._full_template' do
    it 'returns template' do
      component = AwsCodeDeploy.new(@component_name, @test_data['Input']['Initialize']['Valid'])

      allow(Context).to receive_message_chain("component.role_arn").and_return('CodeDeployExecutionRole-123')
      allow(component).to receive(:_is_windows_component?).and_return(false)

      allow(Context).to receive_message_chain('component.variable')
        .with("pipeline", "ArtefactBucketName", nil)
        .and_return("aws-codedeploy-ap-southeast-2")

      allow(Context).to receive_message_chain('component.variable')
        .with("rhel7", "AutoScalingGroupName", nil, '5')
        .and_return(nil)

      result_template = component.send :_full_template

      # app name must be interpolated
      @test_data['Output']['_full_template']['Resources']['MyApp']['Properties']['ApplicationName'] = 'ams01-c031-99-dev-master-5-TestComponent'

      puts "TEST:"
      @test_data['Output']['_full_template'].to_yaml

      expect(result_template).to eq @test_data['Output']['_full_template']
    end
  end

  context '._deployment_groups_template' do
    it 'returns template for instance' do
      component = AwsCodeDeploy.new(@component_name, @test_data['Input']['Initialize']['Valid'])

      allow(Context).to receive_message_chain('component.role_arn').and_return('CodeDeployExecutionRole-123')
      allow(Context).to receive_message_chain('component.variable')
        .with("pipeline", "ArtefactBucketName", nil)
        .and_return("aws-codedeploy-ap-southeast-2")

      allow(Context).to receive_message_chain('component.variable')
        .with("rhel7", "AutoScalingGroupName", nil, anything)
        .and_return(nil)

      allow(Context).to receive_message_chain('component.build_number')
        .with("rhel7")
        .and_return(nil)

      allow(Context).to receive_message_chain("component.replace_variables")

      allow(component).to receive(:_get_deployment_group_name).and_return('ams01-c031-99-dev-master-5-ABCD1')
      allow(component).to receive(:_is_windows_component?).and_return(false)

      result_template = component.__send__(:_deployment_groups_template)

      # app name must be interpolated
      @test_data['Output']['_full_template']['Resources']['MyApp']['Properties']['ApplicationName'] = 'ams01-c031-99-dev-master-5-TestComponent-CodeDeployApp'

      expect(result_template).to eq @test_data['Output']['_deployment_groups_template']
    end

    it 'returns template for autoscale' do
      component = AwsCodeDeploy.new(@component_name, @test_data['Input']['Initialize']['ValidAutoScale'])

      allow(Context).to receive_message_chain('component.role_arn').and_return('CodeDeployExecutionRole-123')
      allow(Context).to receive_message_chain('component.variable')
        .with("pipeline", "ArtefactBucketName", nil)
        .and_return("aws-codedeploy-ap-southeast-2")

      allow(Context).to receive_message_chain('component.variable')
        .with("rhel7-autoscale", "AutoScalingGroupName", nil, anything)
        .and_return('auto-scale-group-name')

      allow(Context).to receive_message_chain('component.build_number')
        .with("rhel7-autoscale")
        .and_return(nil)

      allow(Context).to receive_message_chain("component.replace_variables")

      allow(component).to receive(:_get_deployment_group_name).and_return('ams01-c031-99-dev-master-5-ABCD1')
      allow(component).to receive(:_is_windows_component?).and_return(false)

      result_template = component.__send__(:_deployment_groups_template)

      # app name must be interpolated
      @test_data['Output']['_full_template']['Resources']['MyApp']['Properties']['ApplicationName'] = 'ams01-c031-99-dev-master-5-TestComponent-CodeDeployApp'

      expect(result_template).to eq @test_data['Output']['_deployment_groups_template_autoscale']
    end

    it 'returns template for load balancer' do
      component = AwsCodeDeploy.new(@component_name, @test_data['Input']['Initialize']['ValidLoadBalancer'])

      allow(Context).to receive_message_chain('component.role_arn').and_return('CodeDeployExecutionRole-123')
      allow(Context).to receive_message_chain('component.variable')
        .with("pipeline", "ArtefactBucketName", nil)
        .and_return("aws-codedeploy-ap-southeast-2")

      allow(Context).to receive_message_chain('component.variable')
        .with("rhel7-autoscale", "AutoScalingGroupName", nil, anything)
        .and_return('auto-scale-group-name')

      allow(Context).to receive_message_chain('component.build_number')
        .with("rhel7-autoscale")
        .and_return(nil)

      allow(Context).to receive_message_chain("component.replace_variables")

      allow(component).to receive(:_get_deployment_group_name).and_return('ams01-c031-99-dev-master-5-ABCD1')
      allow(component).to receive(:_is_windows_component?).and_return(false)

      result_template = component.__send__(:_deployment_groups_template)

      # app name must be interpolated
      @test_data['Output']['_full_template']['Resources']['MyApp']['Properties']['ApplicationName'] = 'ams01-c031-99-dev-master-5-TestComponent-CodeDeployApp'

      expect(result_template).to eq @test_data['Output']['_deployment_groups_template_loadbalancer']
    end

    it 'updates existing template' do
      component = AwsCodeDeploy.new(@component_name, @test_data['Input']['Initialize']['ValidUpdateRevision'])

      allow(Context).to receive_message_chain('component.role_arn').and_return('CodeDeployExecutionRole-123')
      allow(Context).to receive_message_chain('component.variable')
        .with("pipeline", "ArtefactBucketName", nil)
        .and_return("aws-codedeploy-ap-southeast-2")

      allow(Context).to receive_message_chain('component.variable')
        .with("rhel7-update-revision", "AutoScalingGroupName", nil, anything)
        .and_return(nil)

      allow(Context).to receive_message_chain('component.build_number')
        .with("rhel7-update-revision")
        .and_return(nil)

      allow(Context).to receive_message_chain("component.replace_variables")

      allow(component).to receive(:_get_deployment_group_name).and_return('ams01-c031-99-dev-master-5-ABCD1')
      allow(component).to receive(:_is_windows_component?).and_return(false)

      result_template = component.__send__(
        :_deployment_groups_template,
        :custom_resource_name => 'new-revision-for-build-6',
        :existing_template => @test_data['Output']['_deployment_groups_template_update_revision']
      )

      # app name must be interpolated
      @test_data['Output']['_full_template']['Resources']['MyApp']['Properties']['ApplicationName'] = 'ams01-c031-99-dev-master-5-TestComponent-CodeDeployApp'
      expect(result_template).to eq @test_data['Output']['_deployment_groups_template_update_revision_output']
    end
  end

  context '._update_security_rules' do
    it 'deploys new security rules' do
      component = AwsCodeDeploy.new(@component_name, @test_data['Input']['Initialize']['Valid'])

      allow(AwsHelper).to receive(:cfn_stack_exists).and_return(nil)

      expect { component.send(:_update_security_rules) }.not_to raise_exception
    end

    it 'updates existing security rules' do
      component = AwsCodeDeploy.new(@component_name, @test_data['Input']['Initialize']['Valid'])

      allow(AwsHelper).to receive(:cfn_stack_exists).and_return('existing-stack-id')

      expect { component.send(:_update_security_rules) }.not_to raise_exception
    end
  end

  context '.get_target_component_name' do
    it 'returns value' do
      component = AwsCodeDeploy.new(@component_name, @test_data['Input']['Initialize']['Valid'])

      expect(component.get_target_component_name).to eq('rhel7')
    end
  end

  context '._get_revision_archive_type' do
    it 'returns tar.gz' do
      component = AwsCodeDeploy.new(@component_name, @test_data['Input']['Initialize']['Valid'])
      allow(component).to receive(:_is_windows_component?).and_return(false)

      expect(component.send(:_get_revision_archive_type)).to eq('tgz')
    end

    it 'returns zip' do
      component = AwsCodeDeploy.new(@component_name, @test_data['Input']['Initialize']['Valid'])
      allow(component).to receive(:_is_windows_component?).and_return(true)

      expect(component.send(:_get_revision_archive_type)).to eq('zip')
    end
  end

  context '._get_revision_extension' do
    it 'returns tar.gz' do
      component = AwsCodeDeploy.new(@component_name, @test_data['Input']['Initialize']['Valid'])
      allow(component).to receive(:_is_windows_component?).and_return(false)

      expect(component.send(:_get_revision_extension)).to eq('tar.gz')
    end

    it 'returns zip' do
      component = AwsCodeDeploy.new(@component_name, @test_data['Input']['Initialize']['Valid'])
      allow(component).to receive(:_is_windows_component?).and_return(true)

      expect(component.send(:_get_revision_extension)).to eq('zip')
    end
  end

  context '._is_windows_component' do
    it 'returns true' do
      component = AwsCodeDeploy.new(@component_name, @test_data['Input']['Initialize']['Valid'])

      allow(Consumable).to receive(:get_consumable_definitions).and_return({})
      allow(Defaults).to receive(:codedeploy_win_component?).and_return(true)

      expect(component.send(:_is_windows_component?)).to eq(true)
    end

    it 'returns false' do
      component = AwsCodeDeploy.new(@component_name, @test_data['Input']['Initialize']['Valid'])

      allow(Consumable).to receive(:get_consumable_definitions).and_return({})
      allow(Defaults).to receive(:codedeploy_win_component?).and_return(false)

      expect(component.send(:_is_windows_component?)).to eq(false)
    end
  end

  context '.update_active_build?' do
    it 'returns true by default' do
      component = AwsCodeDeploy.new(@component_name, @test_data['Input']['Initialize']['Valid'])

      allow(Defaults).to receive(:is_codedeploy_deployment_mode?).and_return(false)

      expect(component.update_active_build?).to eq(true)
    end

    it 'returns false in codedeploy mode' do
      component = AwsCodeDeploy.new(@component_name, @test_data['Input']['Initialize']['Valid'])

      allow(Defaults).to receive(:is_codedeploy_deployment_mode?).and_return(true)

      expect(component.update_active_build?).to eq(false)
    end
  end

  context '._get_tags' do
    it 'returns values' do
      sections = {
        :ams => 'ams',
        :qda => 'qda',
        :as => 'as',
        :ase => 'ase',
        :asbp_type => 'asbp_type'
      }

      allow(Defaults).to receive(:sections) .and_return({ :env => 'nonp' }.merge(sections))
      component = AwsCodeDeploy.new(@component_name, @test_data['Input']['Initialize']['Valid'])
      tags = component.send(:_get_tags)

      expect(tags).to include({ :key => "feature_datadog", :value => "disabled" })

      allow(Defaults).to receive(:sections) .and_return({ :env => 'prod' }.merge(sections))
      component = AwsCodeDeploy.new(@component_name, @test_data['Input']['Initialize']['Valid'])
      tags = component.send(:_get_tags)

      expect(tags).to include({ :key => "feature_datadog", :value => "disabled" })
    end
  end
end # RSpec.describe
