$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib/context/"))
$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib/context/storage"))
require 'kms_context.rb'
require 's3_state_storage.rb'
RSpec.describe KmsContext do
  before(:context) do
  end

  context '._secrets_context' do
    it 'handles secrets_context' do
      sections = {
        ams: 'ams01',
        qda: 'c031',
        as: '01',
        branch: 'master',
        ase: 'dev',
        build: '05',
        env: 'prod'
      }

      dummy_storage = double(Object)
      context = KmsContext.new(dummy_storage, sections)
      allow(dummy_storage).to receive(:load) .and_return(sections)
      result = context.send(:_secrets_context)

      expect(result).to eq(sections)
    end

    it 'loading context if secrets_context is nil' do
      sections = {
        ams: 'ams01',
        qda: 'c031',
        as: '01',
        branch: 'master',
        ase: 'dev',
        build: '05',
        env: 'prod'
      }

      dummy_storage = double(Object)
      context = KmsContext.new(dummy_storage, sections)

      allow(dummy_storage).to receive(:load) .and_return({ 'a' => 1 })

      context.instance_variable_set(:@secrets_context, nil)

      result = {}
      result = context.send(:_secrets_context)

      allow(context).to receive(:secrets_key_arn) .and_return('new KmsKeyArn')

      expect(result).to eq({ 'a' => 1 })
    end

    it 'updates KmsKeyArn' do
      sections = {
        ams: 'ams01',
        qda: 'c031',
        as: '01',
        branch: 'master',
        ase: 'dev',
        build: '05',
        env: 'prod'
      }

      dummy_storage = double(Object)
      context = KmsContext.new(dummy_storage, sections)

      allow(dummy_storage).to receive(:load) .and_return({ 'a' => 1, 'KeyArn' => 'new KmsKeyArn' })

      expect(Context).to receive_message_chain('component.set_variables')

      context.instance_variable_set(:@secrets_context, nil)
      context.send(:_secrets_context)
    end
  end
end # RSpec.describe
