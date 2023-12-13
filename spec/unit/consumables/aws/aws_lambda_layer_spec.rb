$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws")
require 'aws_lambda_layer'
require 'builders/lambda_layer_builder'

RSpec.describe AwsLambdaLayer do
  before(:context) do
    test_data_file = "#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"
    @test_data = YAML.load_file(test_data_file)['UnitTest']
  end

  context '.initialize' do
    it 'initialize without error' do
      expect { AwsLambdaLayer.new 'correct', @test_data['Input']['initialize']['correct'] }.not_to raise_exception
    end

    it 'fail initialize with error - multiple' do
      expect { AwsLambdaLayer.new 'multiple', @test_data['Input']['initialize']['multiple'] }
        .to raise_error(RuntimeError, /This component does not support multiple AWS::Lambda::LayerVersion resources/)
    end

    it 'fail initialize with error - wrong-type' do
      expect { AwsLambdaLayer.new 'wrong-type', @test_data['Input']['initialize']['wrong-type'] }
        .to raise_error(RuntimeError, /is not supported by this component/)
    end

    it 'fail initialize with error - wrong-content' do
      expect { AwsLambdaLayer.new 'wrong-content', @test_data['Input']['initialize']['wrong-content'] }
        .to raise_error(RuntimeError, /Lambda Layer 'Content' property must be specified as a zip file/)
    end
  end

  context '._upload_package_artefact' do
    it 'fails to upload lambda package artefact' do
      aws_lambda_layer = AwsLambdaLayer.new 'correct', @test_data['Input']['initialize']['correct']
      allow(Context).to receive_message_chain('s3.artefact_bucket_name').and_return('arn:aws:s3:::qf-ams01-c031-n-01')
      allow(Context).to receive_message_chain('s3.lambda_artefact_bucket_name').and_return('arn:aws:s3:::qf-ams01-c031-n-01')
      allow(Defaults).to receive(:cd_artefact_path).and_return('cd/ams01/c031/01/dev/master/1')
      allow(Dir).to receive(:mktmpdir)
      allow(AwsHelper).to receive(:s3_download_object).and_raise(/Failed to download object/)
      allow(FileUtils).to receive(:rm_rf)
      expect { aws_lambda_layer.send(:_upload_package_artefact, 'package.zip') }.to raise_error(/Unable to download and unpack/)
    end

    it 'fails to unpack artefact' do
      aws_lambda_layer = AwsLambdaLayer.new 'correct', @test_data['Input']['initialize']['correct']
      allow(Context).to receive_message_chain('s3.artefact_bucket_name').and_return('arn:aws:s3:::qf-ams01-c031-n-01')
      allow(Context).to receive_message_chain('s3.lambda_artefact_bucket_name').and_return('arn:aws:s3:::qf-ams01-c031-n-01')
      allow(Defaults).to receive(:cd_artefact_path).and_return('cd/ams01/c031/01/dev/master/1')
      allow(AwsHelper).to receive(:s3_download_object)
      allow(aws_lambda_layer).to receive(:untgz!)
      expect { aws_lambda_layer.send(:_upload_package_artefact, 'package.zip') }.to raise_error(/Unable to locate/)
    end

    it 'fails to upload lambda package artefact' do
      aws_lambda_layer = AwsLambdaLayer.new 'correct', @test_data['Input']['initialize']['correct']
      allow(Context).to receive_message_chain('s3.artefact_bucket_name').and_return('arn:aws:s3:::qf-ams01-c031-n-01')
      allow(Context).to receive_message_chain('s3.lambda_artefact_bucket_name').and_return('arn:aws:s3:::qf-ams01-c031-n-01')
      allow(Defaults).to receive(:cd_artefact_path).and_return('cd/ams01/c031/01/dev/master/1')
      allow(AwsHelper).to receive(:s3_download_object)
      allow(aws_lambda_layer).to receive(:untgz!)
      allow(File).to receive(:exist?).and_return(true)
      allow(File).to receive(:basename).and_return('package.zip')
      allow(AwsHelper).to receive(:s3_upload_file).and_raise(/Failed to upload/)
      expect { aws_lambda_layer.send(:_upload_package_artefact, 'package.zip') }.to raise_error(/Unable to upload/)
    end
  end

  before (:context) do
    @aws_lambda_layer = AwsLambdaLayer.new 'correct', @test_data['Input']['initialize']['correct']
  end

  context '.deploy' do
    it 'deploys with new function stack successfully' do
        allow(@aws_lambda_layer).to receive(:_upload_package_artefact)
        allow(@aws_lambda_layer).to receive(:_layer_template).and_return({})

        # Mock creation of a function stack
        allow(AwsHelper).to receive(:cfn_stack_exists).and_return(nil)
        allow(AwsHelper).to receive(:cfn_create_stack).and_return(
            'StackId' => 'dummy-stack-id',
            'StackName' => 'dummy-stack-name'
        )
        allow(Context).to receive_message_chain('component.set_variables')
        expect { @aws_lambda_layer.deploy }.not_to raise_error
    end

    it 'fails to create function stack' do
      allow(@aws_lambda_layer).to receive(:_upload_package_artefact)
      allow(@aws_lambda_layer).to receive(:_layer_template).and_return({})

      # Mock creation of a function stack
      allow(AwsHelper).to receive(:cfn_stack_exists).and_return(nil)
      allow(Context).to receive_message_chain('component.set_variables')
      allow(AwsHelper).to receive(:cfn_create_stack).and_raise(ActionError.new)

      expect { @aws_lambda_layer.deploy }.to raise_error(/Failed to create Lambda Layer stack/)
    end
  end

  before (:context) do
    @aws_lambda_layer = AwsLambdaLayer.new 'correct', @test_data['Input']['initialize']['correct']
  end

  context '.release' do
    it 'success' do
        expect { @aws_lambda_layer.release } .not_to raise_error
      end
  end

  before (:context) do
    @aws_lambda_layer = AwsLambdaLayer.new 'correct', @test_data['Input']['initialize']['correct']
  end

  context '.teardown' do
    it 'teardown of release, version and function stacks successfully' do
      # Mock teardown of the Release stack
      allow(Context).to receive_message_chain('component.stack_id').and_return('dummy-release-stack-id')
      allow(Context).to receive_message_chain('persist.released_build_number').and_return(19)
      allow(Defaults).to receive(:sections).and_return({ build: 19 })
      allow(Context).to receive_message_chain('component.variable').and_return('dummy-release-stack-id')
      allow(AwsHelper).to receive(:cfn_delete_stack).and_return(nil)
      expect { @aws_lambda_layer.teardown }.not_to raise_error
    end
  end

  context '._layer_template' do
    it 'returns template' do
        aws_lambda_layer = AwsLambdaLayer.new('layer', @test_data['Input']['_full_template']['Valid'])

        allow(Context).to receive_message_chain("s3.lambda_artefact_bucket_name")
            .and_return('qcp-pipeline-lambda-artefacts')
        allow(Context).to receive_message_chain("component.replace_variables")
        template = aws_lambda_layer.send(:_layer_template)

        expect(template).to eq @test_data['Output']['_full_template']['Valid']
    end
  end
end # RSpec.describe