$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws")
require 'aws_lambda'
require 'builders/lambda_function_builder'

RSpec.describe AwsLambda do
  before(:context) do
    test_data_file = "#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"
    @test_data = YAML.load_file(test_data_file)['UnitTest']
  end

  context '.initialize' do
    it 'initialize without error' do
      expect { AwsLambda.new 'correct', @test_data['Input']['initialize']['correct'] }.not_to raise_exception
    end

    it 'fail initialize with error - multiple' do
      expect { AwsLambda.new 'multiple', @test_data['Input']['initialize']['multiple'] }
        .to raise_error(RuntimeError, /Multiple AWS::Lambda::Function resources found/)
    end

    it 'fail initialize with error - wrong-type' do
      expect { AwsLambda.new 'wrong-type', @test_data['Input']['initialize']['wrong-type'] }
        .to raise_error(RuntimeError, /is not supported by this component/)
    end

    it 'fail initialize with error - wrong-code' do
      expect { AwsLambda.new 'wrong-code', @test_data['Input']['initialize']['wrong-code'] }
        .to raise_error(RuntimeError, /Lambda 'Code' property must be specified as a jar or zip file/)
    end
  end

  context '.security_items' do
    it 'returns security items' do
      aws_lambda = AwsLambda.new 'correct', @test_data['Input']['initialize']['correct']
      allow(Context).to receive_message_chain('asir.managed_policy_arn')
      expect(aws_lambda.security_items).to be_a(Array)
    end
  end

  context '.security_rules' do
    it 'returns security rules' do
      aws_lambda = AwsLambda.new 'correct', @test_data['Input']['initialize']['correct']
      allow(Context).to receive_message_chain('component.variable')
      expect(aws_lambda.security_rules).to be_a(Array)
    end

    it 'returns security rules for DeadLetter' do
      aws_lambda = AwsLambda.new 'correct', @test_data['Input']['initialize']['deadletter']
      allow(Context).to receive_message_chain('component.variable')
      allow(Context).to receive_message_chain('component.replace_variables')
      expect(aws_lambda.security_rules).to be_a(Array)
    end
  end

  context '.name_records' do
    it 'return name records' do
      aws_lambda = AwsLambda.new 'correct', @test_data['Input']['initialize']['correct']
      allow(aws_lambda).to receive(:_deploy_alias_arn)
      allow(aws_lambda).to receive(:_release_alias_arn)
      expect(aws_lambda.name_records).to be_a(Hash)
    end
  end

  context '.security_rules' do
    it 'returns security rules' do
      aws_lambda = AwsLambda.new 'correct', @test_data['Input']['initialize']['correct']
      allow(Context).to receive_message_chain('component.variable')
      expect(aws_lambda.security_rules).to be_a(Array)
    end
  end

  context '._release_alias_arn' do
    it 'returns _release_alias_arn' do
      aws_lambda = AwsLambda.new 'correct', @test_data['Input']['initialize']['correct']
      allow(Context).to receive_message_chain('environment.region')
      allow(Context).to receive_message_chain('environment.account_id')
      allow(Context).to receive_message_chain('component.variable').and_return('Dummy-Function-Name')
      expect(aws_lambda.send(:_release_alias_arn)).to be_a(String)
    end
  end

  context '._deploy_alias_arn' do
    it 'returns _deploy_alias_arn' do
      aws_lambda = AwsLambda.new 'correct', @test_data['Input']['initialize']['correct']
      allow(Context).to receive_message_chain('environment.region')
      allow(Context).to receive_message_chain('environment.account_id')
      allow(Defaults).to receive(:sections).and_return({})
      allow(aws_lambda).to receive(:_lambda_function_name)
      allow(Context).to receive_message_chain('component.variable').and_return('Function')
      expect(aws_lambda.send(:_deploy_alias_arn)).to be_a(String)
    end
  end

  context '._version_template' do
    it 'returns lambda version template' do
      aws_lambda = AwsLambda.new 'correct', @test_data['Input']['initialize']['correct']
      allow(aws_lambda).to receive(:_process_lambda_version)
      allow(aws_lambda).to receive(:_process_lambda_alias)
      allow(aws_lambda).to receive(:_process_lambda_permission)
      allow(Defaults).to receive(:sections).and_return({ build: 19 })
      template = aws_lambda.send(:_version_template, {})
      expect(template).to be_a(Hash)
    end

    it 'returns template with event with blank input' do
      aws_lambda = AwsLambda.new('function', @test_data['Input']['_full_template']['Valid'])
      allow(aws_lambda).to receive(:_process_lambda_version)
      allow(aws_lambda).to receive(:_process_lambda_alias)
      allow(aws_lambda).to receive(:_process_lambda_permission)
      allow(Defaults).to receive(:sections).and_return({ build: 19 })
      template = aws_lambda.send(:_version_template, {})

      expect(template).to eq @test_data['Output']['_version_template']['Valid']
    end

    it 'returns template with event with no input' do
      aws_lambda = AwsLambda.new('function', @test_data['Input']['_full_template']['CloudwatchEvents'])
      allow(aws_lambda).to receive(:_process_lambda_version)
      allow(aws_lambda).to receive(:_process_lambda_alias)
      allow(aws_lambda).to receive(:_process_lambda_permission)
      allow(Defaults).to receive(:sections).and_return({ build: 19 })
      template = aws_lambda.send(:_version_template, {})

      expect(template).to eq @test_data['Output']['_version_template']['CloudwatchEvents']
    end
  end

  context '._release_template' do
    it 'returns lambda release template' do
      aws_lambda = AwsLambda.new 'correct', @test_data['Input']['initialize']['correct']
      allow(aws_lambda).to receive(:_process_lambda_alias)
      template = aws_lambda.send(:_release_template, 'function', {})
      expect(template).to be_a(Hash)
    end
  end

  context '._lambda_function_name' do
    it 'returns lambda function name' do
      aws_lambda = AwsLambda.new 'correct', @test_data['Input']['initialize']['correct']
      allow(Defaults).to receive(:sections).and_return(
        ams: 'ams01',
        qda: 'c031',
        build: 19,
        as: '01',
        ase: 'dev',
        branch: 'master'
      )
      function_name = aws_lambda.send(:_lambda_function_name)
      expect(function_name).to eq('ams01-c031-01-dev-master-correct')
    end
  end

  context '._lambda_function_stack_name' do
    it 'returns lambda function stack name' do
      aws_lambda = AwsLambda.new 'correct', @test_data['Input']['initialize']['correct']
      allow(Defaults).to receive(:sections).and_return(
        ams: 'ams01',
        qda: 'c031',
        build: 19,
        as: '01',
        ase: 'dev',
        branch: 'master'
      )
      function_stack_name = aws_lambda.send(:_lambda_function_stack_name)
      expect(function_stack_name).to eq('ams01-c031-01-dev-master-correct-Latest')
    end
  end

  context '._lambda_release_stack_name' do
    it 'returns lambda function name' do
      aws_lambda = AwsLambda.new 'correct', @test_data['Input']['initialize']['correct']
      allow(Defaults).to receive(:sections).and_return(
        ams: 'ams01',
        qda: 'c031',
        build: 19,
        as: '01',
        ase: 'dev',
        branch: 'master'
      )
      release_stack_name = aws_lambda.send(:_lambda_release_stack_name)
      expect(release_stack_name).to eq('ams01-c031-01-dev-master-correct-Release')
    end
  end

  context '._base_service_permissions' do
    it 'returns lambda base service permissions template' do
      aws_lambda = AwsLambda.new 'correct', @test_data['Input']['initialize']['correct']
      allow(Context).to receive_message_chain('s3.as_bucket_arn').and_return('arn:aws:s3:::qf-ams01-c031-n-01')
      base_service_permission = aws_lambda.send(:_base_service_permissions, 'Function')
      expect(base_service_permission).to eq({
        'S3ASBucketPermission' => {
          'Type' => 'AWS::Lambda::Permission',
          'Properties' => {
            'Action' => 'lambda:InvokeFunction',
            'FunctionName' => { 'Ref' => 'FunctionVersion' },
            'Principal' => 's3.amazonaws.com',
            'SourceArn' => 'arn:aws:s3:::qf-ams01-c031-n-01'
          }
        },
        'S3ASBucketPermissionForDeployAlias' => {
          'Type' => 'AWS::Lambda::Permission',
          'Properties' => {
            'Action' => 'lambda:InvokeFunction',
            'FunctionName' => { 'Ref' => 'Deploy' },
            'Principal' => 's3.amazonaws.com',
            'SourceArn' => 'arn:aws:s3:::qf-ams01-c031-n-01'
          }
        }
      })
    end
  end

  context '._upload_package_artefact' do
    it 'fails to upload lambda package artefact' do
      aws_lambda = AwsLambda.new 'correct', @test_data['Input']['initialize']['correct']
      allow(Context).to receive_message_chain('s3.artefact_bucket_name').and_return('arn:aws:s3:::qf-ams01-c031-n-01')
      allow(Context).to receive_message_chain('s3.lambda_artefact_bucket_name').and_return('arn:aws:s3:::qf-ams01-c031-n-01')
      allow(Defaults).to receive(:cd_artefact_path).and_return('cd/ams01/c031/01/dev/master/1')
      allow(Dir).to receive(:mktmpdir)
      allow(AwsHelper).to receive(:s3_download_object).and_raise(/Failed to download object/)
      allow(FileUtils).to receive(:rm_rf)
      expect { aws_lambda.send(:_upload_package_artefact, 'package.zip') }.to raise_error(/Unable to download and unpack/)
    end

    it 'fails to unpack artefact' do
      aws_lambda = AwsLambda.new 'correct', @test_data['Input']['initialize']['correct']
      allow(Context).to receive_message_chain('s3.artefact_bucket_name').and_return('arn:aws:s3:::qf-ams01-c031-n-01')
      allow(Context).to receive_message_chain('s3.lambda_artefact_bucket_name').and_return('arn:aws:s3:::qf-ams01-c031-n-01')
      allow(Defaults).to receive(:cd_artefact_path).and_return('cd/ams01/c031/01/dev/master/1')
      allow(AwsHelper).to receive(:s3_download_object)
      allow(aws_lambda).to receive(:untgz!)
      expect { aws_lambda.send(:_upload_package_artefact, 'package.zip') }.to raise_error(/Unable to locate/)
    end

    it 'fails to upload lambda package artefact' do
      aws_lambda = AwsLambda.new 'correct', @test_data['Input']['initialize']['correct']
      allow(Context).to receive_message_chain('s3.artefact_bucket_name').and_return('arn:aws:s3:::qf-ams01-c031-n-01')
      allow(Context).to receive_message_chain('s3.lambda_artefact_bucket_name').and_return('arn:aws:s3:::qf-ams01-c031-n-01')
      allow(Defaults).to receive(:cd_artefact_path).and_return('cd/ams01/c031/01/dev/master/1')
      allow(AwsHelper).to receive(:s3_download_object)
      allow(aws_lambda).to receive(:untgz!)
      allow(File).to receive(:exist?).and_return(true)
      allow(File).to receive(:basename).and_return('package.zip')
      allow(AwsHelper).to receive(:s3_upload_file).and_raise(/Failed to upload/)
      expect { aws_lambda.send(:_upload_package_artefact, 'package.zip') }.to raise_error(/Unable to upload/)
    end
  end

  before (:context) do
    @aws_lambda = AwsLambda.new 'correct', @test_data['Input']['initialize']['correct']
  end

  context '.deploy' do
    it 'deploys with new function stack successfully' do
      allow(@aws_lambda).to receive(:_upload_package_artefact)
      allow(@aws_lambda).to receive(:_update_security_rules)
      allow(@aws_lambda).to receive(:_lambda_function_stack_name).and_return('ams01-c031-01-dev-master-correct-Latest')
      allow(@aws_lambda).to receive(:_function_template).and_return({})

      # Mock creation of a function stack
      allow(AwsHelper).to receive(:cfn_stack_exists).and_return(nil)
      allow(AwsHelper).to receive(:cfn_create_stack).and_return(
        'StackId' => 'dummy-stack-id',
        'StackName' => 'dummy-stack-name'
      )
      allow(Context).to receive_message_chain('component.set_variables')

      # Mock creation of a version stack
      allow(Context).to receive_message_chain('component.variable')
      allow(AwsHelper).to receive(:cfn_create_stack).and_return(
        'StackId' => 'dummy-version-stack-id',
        'StackName' => 'dummy-version-stack-name'
      )
      allow(@aws_lambda).to receive(:_deploy_alias_arn).and_return(
        'arn:aws:lambda:ap-southeast-2:123456789012:function:function-build-19'
      )
      allow(Context).to receive_message_chain('component.set_variables')
      allow(Context).to receive_message_chain('component.replace_variables').and_return({})
      expect { @aws_lambda.deploy }.not_to raise_error
    end

    it 'deploys with with update to function stack successfully' do
      allow(@aws_lambda).to receive(:_upload_package_artefact)
      allow(@aws_lambda).to receive(:_update_security_rules)
      allow(@aws_lambda).to receive(:_lambda_function_stack_name).and_return('ams01-c031-01-dev-master-correct-Latest')
      allow(@aws_lambda).to receive(:_function_template).and_return({})

      # Mock creation of a function stack
      allow(AwsHelper).to receive(:cfn_stack_exists).and_return('dummy-function-stack-id')
      allow(AwsHelper).to receive(:cfn_update_stack).and_return(
        'StackId' => 'dummy-stack-id',
        'StackName' => 'dummy-stack-name'
      )
      allow(Context).to receive_message_chain('component.set_variables')

      # Mock creation of a version stack
      allow(Context).to receive_message_chain('component.variable')
      allow(AwsHelper).to receive(:cfn_create_stack).and_return(
        'StackId' => 'dummy-version-stack-id',
        'StackName' => 'dummy-version-stack-name'
      )
      allow(@aws_lambda).to receive(:_deploy_alias_arn).and_return(
        'arn:aws:lambda:ap-southeast-2:123456789012:function:function-build-19'
      )
      allow(Context).to receive_message_chain('component.set_variables')
      allow(Context).to receive_message_chain('component.replace_variables').and_return({})
      expect { @aws_lambda.deploy }.not_to raise_error
    end

    it 'fails to create/update function stack' do
      allow(@aws_lambda).to receive(:_upload_package_artefact)
      allow(@aws_lambda).to receive(:security_rules)
      allow(@aws_lambda).to receive(:_update_security_rules)
      allow(@aws_lambda).to receive(:_lambda_function_stack_name).and_return('ams01-c031-01-dev-master-correct-Latest')
      allow(@aws_lambda).to receive(:_function_template).and_return({})

      # Mock creation of a function stack
      allow(AwsHelper).to receive(:cfn_stack_exists).and_return(nil)
      allow(Context).to receive_message_chain('component.set_variables')
      allow(AwsHelper).to receive(:cfn_create_stack).and_raise(ActionError.new)

      expect { @aws_lambda.deploy }.to raise_error(/Failed to create lambda function stack/)
    end

    it 'fails to create version stack' do
      allow(@aws_lambda).to receive(:_upload_package_artefact)
      allow(@aws_lambda).to receive(:_update_security_rules)
      allow(@aws_lambda).to receive(:_lambda_function_stack_name).and_return('ams01-c031-01-dev-master-correct-Latest')
      allow(@aws_lambda).to receive(:_function_template).and_return({})

      # Mock creation of a function stack
      allow(AwsHelper).to receive(:cfn_stack_exists).and_return('dummy-function-stack-id')
      allow(AwsHelper).to receive(:cfn_update_stack).and_return(
        'StackId' => 'dummy-stack-id',
        'StackName' => 'dummy-stack-name'
      )
      allow(Context).to receive_message_chain('component.set_variables')
      allow(Context).to receive_message_chain('component.replace_variables').and_return({})

      # Mock creation of a version stack
      allow(Context).to receive_message_chain('component.variable')
      allow(AwsHelper).to receive(:cfn_create_stack).and_raise(ActionError.new)
      expect { @aws_lambda.deploy }.to raise_error /Failed to create or update lambda version stack/
    end
  end

  before (:context) do
    @aws_lambda = AwsLambda.new 'correct', @test_data['Input']['initialize']['correct']
  end

  context '.release' do
    it 'release with new function stack successfully' do
      allow(@aws_lambda).to receive(:_lambda_release_stack_name)
      allow(Context).to receive_message_chain('component.variable').and_return('dummy-funciton-name')
      allow(Context).to receive_message_chain('component.variable').and_return('dummy-function-version')
      allow(@aws_lambda).to receive(:_release_template)

      # Mock creation of a release stack
      allow(AwsHelper).to receive(:cfn_stack_exists).and_return(nil)
      allow(AwsHelper).to receive(:cfn_create_stack).and_return(
        'StackId' => 'dummy-stack-id',
        'StackName' => 'dummy-stack-name'
      )
      allow(@aws_lambda).to receive(:_release_alias_arn).and_return('dummy-release-arn')
      allow(Context).to receive_message_chain('component.set_variables')
      expect { @aws_lambda.release }.not_to raise_error
    end

    it 'release with update to existing function stack successfully' do
      allow(@aws_lambda).to receive(:_lambda_release_stack_name)
      allow(Context).to receive_message_chain('component.variable').and_return('dummy-funciton-name')
      allow(Context).to receive_message_chain('component.variable').and_return('dummy-function-version')
      allow(@aws_lambda).to receive(:_release_template)

      # Mock creation of a release stack
      allow(AwsHelper).to receive(:cfn_stack_exists).and_return('dummy-stack-id')
      allow(AwsHelper).to receive(:cfn_update_stack).and_return(
        'StackId' => 'dummy-stack-id',
        'StackName' => 'dummy-stack-name'
      )
      allow(@aws_lambda).to receive(:_release_alias_arn).and_return('dummy-release-arn')
      allow(Context).to receive_message_chain('component.set_variables')
      expect { @aws_lambda.release }.not_to raise_error
    end

    it 'release with update to existing function stack successfully' do
      allow(@aws_lambda).to receive(:_lambda_release_stack_name)
      allow(Context).to receive_message_chain('component.variable').and_return('dummy-funciton-name')
      allow(Context).to receive_message_chain('component.variable').and_return('dummy-function-version')
      allow(@aws_lambda).to receive(:_release_template)

      # Mock creation of a release stack
      allow(AwsHelper).to receive(:cfn_stack_exists).and_return('dummy-stack-id')
      allow(AwsHelper).to receive(:cfn_update_stack).and_raise(ActionError.new)
      allow(Context).to receive_message_chain('component.set_variables')
      expect { @aws_lambda.release }.to raise_error(/Failed to create or update release alias stack/)
    end
  end

  before (:context) do
    @aws_lambda = AwsLambda.new 'correct', @test_data['Input']['initialize']['correct']
  end

  context '.teardown' do
    it 'teardown of release, version and function stacks successfully' do
      # Mock teardown of the Release stack
      allow(Context).to receive_message_chain('persist.released_build_number').and_return(19)
      allow(Defaults).to receive(:sections).and_return({ build: 19 })
      allow(Context).to receive_message_chain('component.variable').and_return('dummy-release-stack-id')
      allow(AwsHelper).to receive(:cfn_delete_stack).and_return(nil)

      # Mock teardown of the version stack
      allow(Context).to receive_message_chain('component.stack_id').and_return('dummy-version-stack-id')
      allow(AwsHelper).to receive(:cfn_delete_stack).and_return(nil)

      # Mock lookup of version lookup
      allow(Context).to receive_message_chain('component.variable').and_return('dummy-function-name')
      allow(AwsHelper).to receive(:lambda_versions).and_return([])

      # Mock teardown of the latest function stack
      allow(Context).to receive_message_chain('component.variable').and_return('dummy-function-stack-id')
      allow(AwsHelper).to receive(:cfn_delete_stack).and_return(nil)

      expect { @aws_lambda.teardown }.not_to raise_error
    end

    it 'fail teardown of release, version and function stacks' do
      # Mock teardown of the Release stack
      allow(Context).to receive_message_chain('persist.released_build_number').and_return(19)
      allow(Defaults).to receive(:sections).and_return({ build: 19 })
      allow(Context).to receive_message_chain('component.variable').and_return('dummy-release-stack-id')
      allow(AwsHelper).to receive(:cfn_delete_stack).and_raise(ActionError)

      # Mock teardown of the version stack
      allow(Context).to receive_message_chain('component.stack_id').and_return('dummy-version-stack-id')
      allow(AwsHelper).to receive(:cfn_delete_stack).and_raise(ActionError)

      # Mock lookup of version lookup
      allow(Context).to receive_message_chain('component.variable').and_return('dummy-function-name')
      allow(AwsHelper).to receive(:lambda_versions).and_raise(ActionError)

      # Mock teardown of the latest function stack
      allow(Context).to receive_message_chain('component.variable').and_return('dummy-function-stack-id')
      allow(AwsHelper).to receive(:cfn_delete_stack).and_raise(ActionError)

      expect { @aws_lambda.teardown }.to raise_exception(ActionError)
    end
  end

  context '._function_template' do
    it 'returns template' do
      aws_lambda = AwsLambda.new('function', @test_data['Input']['_full_template']['Valid'])
      allow(Context).to receive_message_chain("environment.subnet_ids")
        .and_return(["subnet-123", "subnet-456"])
      allow(Context).to receive_message_chain("component.sg_id")
        .and_return(['sg-1234566'])
      allow(Context).to receive_message_chain('asir.source_sg_id').and_return('source-asir-sg')
      allow(Context).to receive_message_chain("component.role_arn")
        .and_return('InstanceRoleName-123')
      allow(Context).to receive_message_chain("s3.lambda_artefact_bucket_name")
        .and_return('qcp-pipeline-lambda-artefacts')
      allow(Context).to receive_message_chain("component.replace_variables")
      template = aws_lambda.send(:_function_template)
      

      expect(template).to eq @test_data['Output']['_full_template']['Valid']
    end
  end
end # RSpec.describe 
