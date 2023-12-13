$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws/builders")
require 'lambda_layer_builder'

RSpec.describe LambdaLayerBuilder do
  before(:context) do
    @dummy_class = DummyClass.new
    @dummy_class.extend(LambdaLayerBuilder)
    @test_data = YAML.load(
      File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml")
    )
  end

  context '._process_lambda_layer' do
    it 'successfully builds template' do
      @test_data['UnitTest']['Input']['_process_lambda_layer'].each_with_index do |definition, index|
        template = { "Resources" => {}, "Outputs" => {} }
        expect {
          @dummy_class._process_lambda_layer(
            template: template,
            layer_definition: definition
          )
        }.not_to raise_error
        expect(template).to eq @test_data['UnitTest']['Output']['_process_lambda_layer'][index]
      end
    end
  end


  context '._upload_package_artefacts' do
    it 'successfully uploads packaged artefacts' do
      require 'util/archive'

      allow(Context).to receive_message_chain('s3.artefact_bucket_name').and_return('dummy-artefact-bucket-name')
      allow(Context).to receive_message_chain('s3.lambda_artefact_bucket_name').and_return('dummy-lambda-artefact-bucket-name')
      allow(Defaults).to receive(:cd_artefact_path).and_return('dummy-path')
      allow(Dir).to receive(:mktmpdir).and_return('dummy-tmp-dir')

      allow(AwsHelper).to receive(:s3_download_object)
      allow(Util::Archive).to receive(:untgz!)
      allow(File).to receive(:exist?).and_return(true)

      allow(AwsHelper).to receive(:s3_upload_file)

      expect {
        @dummy_class._upload_package_artefacts(
          component_name: 'dummy-component',
          artefacts: ['package.zip']
        )
      }.not_to raise_error
    end

    it 'fails with - unable to upload file' do
      require 'util/archive'

      allow(Context).to receive_message_chain('s3.artefact_bucket_name').and_return('dummy-artefact-bucket-name')
      allow(Context).to receive_message_chain('s3.lambda_artefact_bucket_name').and_return('dummy-lambda-artefact-bucket-name')
      allow(Defaults).to receive(:cd_artefact_path).and_return('dummy-path')
      allow(Dir).to receive(:mktmpdir).and_return('dummy-tmp-dir')

      allow(AwsHelper).to receive(:s3_download_object)
      allow(Util::Archive).to receive(:untgz!)
      allow(File).to receive(:exist?).and_return(true)

      allow(AwsHelper).to receive(:s3_upload_file).and_raise StandardError

      expect {
        @dummy_class._upload_package_artefacts(
          component_name: 'dummy-component',
          artefacts: ['package.zip']
        )
      }.to raise_exception /Unable to upload file to/
    end

    it 'successfully uploads packaged artefacts' do
      require 'util/archive'

      allow(Context).to receive_message_chain('s3.artefact_bucket_name').and_return('dummy-artefact-bucket-name')
      allow(Context).to receive_message_chain('s3.lambda_artefact_bucket_name').and_return('dummy-lambda-artefact-bucket-name')
      allow(Defaults).to receive(:cd_artefact_path).and_return('dummy-path')
      allow(Dir).to receive(:mktmpdir).and_return('dummy-tmp-dir')

      allow(AwsHelper).to receive(:s3_download_object)
      allow(Util::Archive).to receive(:untgz!)
      allow(File).to receive(:exist?).and_return(false)

      expect {
        @dummy_class._upload_package_artefacts(
          component_name: 'dummy-component',
          artefacts: ['package.zip']
        )
      }.to raise_exception /Unable to locate/
    end

    it 'fails with - Unable to download and unpack package' do
      require 'util/archive'

      allow(Context).to receive_message_chain('s3.artefact_bucket_name').and_return('dummy-artefact-bucket-name')
      allow(Context).to receive_message_chain('s3.lambda_artefact_bucket_name').and_return('dummy-lambda-artefact-bucket-name')
      allow(Defaults).to receive(:cd_artefact_path).and_return('dummy-path')
      allow(Dir).to receive(:mktmpdir).and_return('dummy-tmp-dir')

      allow(AwsHelper).to receive(:s3_download_object)
      allow(Util::Archive).to receive(:untgz!).and_raise StandardError

      expect {
        @dummy_class._upload_package_artefacts(
          component_name: 'dummy-component',
          artefacts: ['package.zip']
        )
      }.to raise_exception /Unable to download and unpack package/
    end
  end
end # RSpec.describe
