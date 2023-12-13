$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws")
require 'aws_s3_prefix'

RSpec.describe AwsS3prefix do
  before(:context) do
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))['UnitTest']
  end

  context '.initialize' do
    it 'initialize without error' do
      expect { AwsS3prefix.new 'correct', @test_data['Input']['initialize']['correct'] }.not_to raise_exception
    end

    it 'successfully initialize stack with cache-control' do
      expect { AwsS3prefix.new 'with-cache-control', @test_data['Input']['initialize']['with-cache-control'] }.not_to raise_exception
    end

    it 'successfully initialize stack with cache-control' do
      expect { AwsS3prefix.new 'with-cache-control', @test_data['Input']['initialize']['with-cache-control'] }.not_to raise_exception
    end

    it 'fail initialize with error - multiple' do
      expect { AwsS3prefix.new 'multiple', @test_data['Input']['initialize']['multiple'] }
        .to raise_error(RuntimeError, /Multiple AWS::S3::Prefix resources found/)
    end

    it 'fail initialize with error - wrong-type' do
      expect { AwsS3prefix.new 'wrong-type', @test_data['Input']['initialize']['wrong-type'] }
        .to raise_error(RuntimeError, /is not supported by this component/)
    end

    it 'Must specify a property BucketType for resource' do
      expect { AwsS3prefix.new 'nil-bucket-type', @test_data['Input']['initialize']['nil-bucket-type'] }
        .to raise_error(RuntimeError, /Must specify a property BucketType for resource/)
    end
  end

  before (:context) do
    @aws_s3_prefix = AwsS3prefix.new 'correct', @test_data['Input']['initialize']['correct']
  end

  context '.deploy' do
    it 'deployed successfully' do
      allow(Defaults).to receive(:component_stack_name)
      allow(Context).to receive_message_chain('component.set_variables')
      allow(@aws_s3_prefix).to receive(:_check_approved_apps)
      allow(@aws_s3_prefix).to receive(:_upload_public_s3_artefact)
      allow(@aws_s3_prefix).to receive(:_full_template)
      # Mock creation of a stack
      allow(AwsHelper).to receive(:cfn_create_stack).and_return(
        'StackId' => 'dummy-stack-id',
        'StackName' => 'dummy-stack-name'
      )
      allow(Context).to receive_message_chain('component.set_variables')
      allow(Context).to receive_message_chain('component.variable')
      expect { @aws_s3_prefix.deploy }.not_to raise_error
    end

    it 'fails with Failed to create stack' do
      allow(Defaults).to receive(:component_stack_name)
      allow(Context).to receive_message_chain('component.set_variables')
      allow(@aws_s3_prefix).to receive(:_check_approved_apps)
      allow(@aws_s3_prefix).to receive(:_update_security_rules)
      allow(@aws_s3_prefix).to receive(:_upload_public_s3_artefact)
      # Mock creation of a stack
      allow(AwsHelper).to receive(:cfn_create_stack).and_raise(StandardError)

      expect { @aws_s3_prefix.deploy }.to raise_exception /Failed to create stack/
    end
  end

  context '.release' do
    it 'success' do
      allow(@aws_s3_prefix).to receive(:_release_public_s3_artefact)
      expect { @aws_s3_prefix.release } .not_to raise_error
    end
  end

  context '.teardown' do
    it 'successfully executes teardown' do
      allow(@aws_s3_prefix).to receive(:_delete_public_s3_artefact)
      allow(Context).to receive_message_chain('component.stack_id').and_return('dummy-stack-id')
      allow(AwsHelper).to receive(:cfn_delete_stack).and_return(nil)
      allow(AwsHelper).to receive(:s3_delete_objects)
      allow(@aws_s3_prefix).to receive(:_upload_s3_role)
      expect { @aws_s3_prefix.teardown }.not_to raise_exception
    end

    it 'fails to delete stack' do
      allow(Context).to receive_message_chain('component.stack_id').and_return('dummy-stack-id')
      allow(AwsHelper).to receive(:cfn_delete_stack).and_raise(StandardError)
      allow(AwsHelper).to receive(:s3_delete_objects)
      allow(@aws_s3_prefix).to receive(:_upload_s3_role)
      expect { @aws_s3_prefix.teardown }.to raise_exception
    end
  end

  context '._check_approved_apps' do
    it 'check approved applications' do
      expect { @aws_s3_prefix._check_approved_apps }.not_to raise_exception /Application not in approved list/
    end
  end

  context '._get_release_path' do
    it 'check release path' do
      path = nil
      expect { @aws_s3_prefix._get_release_path(path) }.to raise_exception /Null value for Artefact Path/
    end
  end

  context '._upload_s3_role' do
    it 'fails to return s3-upload role client' do
      allow(Defaults).to receive(:proxy).and_return('dummy_proxy')
      allow(Defaults).to receive(:region).and_return('dummy_region')
      allow(Defaults).to receive(:control_role).and_return('arn:aws:iam::aws-account:role/dummy_control_role')
      allow(Defaults).to receive(:provisioning_role).and_return('arn:aws:iam::aws-account:role/dummy_provisioning_role')
      allow(Defaults).to receive(:proxy).and_return(nil)
      allow(AwsHelperClass).to receive(:new).and_return(AwsHelperClass)
      expect { @aws_s3_prefix.send :_upload_s3_role }.not_to raise_exception
    end
  end

  context '._upload_public_s3_artefact' do
    it 'fail to download artefacts' do
      allow(Context).to receive_message_chain('s3.artefact_bucket_name').and_return('arn:aws:s3:::qf-ams01-c031-n-01')
      allow(Defaults).to receive(:cd_artefact_path).and_return('ams01/c005/01/dev/master/66/publics3')
      allow(Dir).to receive(:mktmpdir)
      allow(AwsHelper).to receive(:s3_download_object).and_raise(/Failed to download object/)
      allow(@aws_s3_prefix).to receive(:untgz!)
      allow(FileUtils).to receive(:rm_rf)
      expect { @aws_s3_prefix.send(:_upload_public_s3_artefact) }.to raise_error(/Unable to download and unpack/)
    end

    it 'fails to upload public artefacts' do
      allow(Context).to receive_message_chain('s3.artefact_bucket_name').and_return('arn:aws:s3:::qf-ams01-c031-n-01')
      allow(Context).to receive_message_chain('s3.upload_artefact_bucket').and_return('arn:aws:s3:::qf-static-public-nonprod01')
      allow(Defaults).to receive(:cd_artefact_path).and_return('ams01/c005/01/dev/master/66/publics3')
      allow(AwsHelper).to receive(:s3_download_object)
      allow(@aws_s3_prefix).to receive(:untgz!)
      allow(File).to receive(:exist?).and_return(true)
      allow(AwsHelper).to receive(:s3_upload_file).and_raise(/Unable to upload/)
      expect { @aws_s3_prefix.send(:_upload_public_s3_artefact) }.not_to raise_error(/Unable to upload/)
    end
  end

  context '._delete_public_s3_artefact' do
    it 'successfully delete artefacts' do
      allow(Defaults).to receive(:provisioning_role).and_return('arn:aws:iam::aws-account:role/dummy_provisioning_role')
      allow(Defaults).to receive(:control_role).and_return('arn:aws:iam::aws-account:role/dummy_control_role')
      allow(Context).to receive_message_chain('s3.upload_artefact_bucket').and_return('arn:aws:s3:::qf-static-public-nonprod01')
      mock_client = double(Object)
      allow(@aws_s3_prefix).to receive(:_upload_s3_role).and_return(mock_client)
      allow(mock_client).to receive(:s3_delete_objects)
      expect { @aws_s3_prefix.send(:_delete_public_s3_artefact) }.not_to raise_error
    end

    it 'failed to teardown latest releaed build' do
      allow(Defaults).to receive(:provisioning_role).and_return('arn:aws:iam::aws-account:role/dummy_provisioning_role')
      allow(Defaults).to receive(:control_role).and_return('arn:aws:iam::aws-account:role/dummy_control_role')
      allow(Context).to receive_message_chain('s3.upload_artefact_bucket').and_return('arn:aws:s3:::qf-static-public-nonprod01')
      allow(Context).to receive_message_chain('persist.released_build_number').and_return(3)
      allow(Context).to receive_message_chain('environment.variable.override_variable').and_return(false)
      allow(AwsHelper).to receive(:s3_delete_objects).and_raise(/Failed to delete artefacts/)
      expect { @aws_s3_prefix.send(:_delete_public_s3_artefact) }.not_to raise_error(/ERROR: Teardown of the released build is rejected by pipeline/)
    end
  end

  context '._release_public_s3_artefact' do
    it 'unable to copy' do
      mock_client = double(Object)
      allow(@aws_s3_prefix).to receive(:_upload_s3_role).and_return(mock_client)
      allow(mock_client).to receive(:s3_delete_objects).and_raise(/Failed to copy object/)

      expect { @aws_s3_prefix.send(:_release_public_s3_artefact) }.not_to raise_error(/Unable to copy the artefacts to release path/)
    end
  end
end
