$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib/context/"))
$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib/context/storage"))
require 's3_state_storage.rb'
RSpec.describe S3StateStorage do
  before(:context) do
  end

  context '.initialise' do
    it 'validates input' do
      expect {
        S3StateStorage.new(1, 2)
      }.to raise_exception(/Expected String for parameter 'bucket'/)

      expect {
        S3StateStorage.new('bucket-name', 2)
      }.to raise_exception(/Expected Array for parameter 'prefix'/)

      expect {
        S3StateStorage.new('bucket-name', [1, 2, 3])
      }.not_to raise_exception
    end
  end

  context '.save' do
    it 'saves variables' do
      expect(AwsHelper).to receive(:s3_put_object)

      storage = S3StateStorage.new('bucket-name')
      storage.save(['context-path'], {})
    end

    it 'skips empty variables' do
      expect(AwsHelper).to receive(:s3_put_object).exactly(0).times

      storage = S3StateStorage.new('bucket-name')
      storage.save(['context-path'], nil)
    end

    it 'logs saving error' do
      expect(AwsHelper).to receive(:s3_put_object) { raise 'err' }

      storage = S3StateStorage.new('bucket-name')
      storage.save(['context-path'], {})
    end
  end

  context '.load' do
    it 'loads context for path' do
      allow(AwsHelper).to receive(:s3_get_object).and_return(["a: 1", 1])

      storage = S3StateStorage.new('bucket-name')

      result = storage.load(['context-path'])

      expect(result).to be_kind_of(Hash)
      expect(result["a"]).to eq(1)
    end

    it 'raises exception for wrong path' do
      allow(AwsHelper).to receive(:s3_get_object) .and_raise("err")

      storage = S3StateStorage.new('bucket-name')

      result = []
      result = storage.load('context-path')

      expect(result).to eq(nil)
    end
  end
end # RSpec.describe
