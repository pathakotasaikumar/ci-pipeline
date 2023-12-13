$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws/builders")
require 'kms_key_builder'

RSpec.describe KmsKeyBuilder do
  before(:context) do
    @dummy_class = DummyClass.new
    @dummy_class.extend(KmsKeyBuilder)
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))['UnitTest']
  end

  context '._process_kms_key' do
    it 'updates template for kms key' do
      template = @test_data['Input']['Template']
      definiton = @test_data['Input']['Definition']
      @dummy_class._process_kms_key(template: template, kms_key_definition: definiton, dr_account_id: '123123123', nonp_account_id: '123123124', environment: 'nonp')
      expect(template).to eq @test_data['Output']['_process_kms_key']
    end

    it 'template when enviorment is prod' do
      template = @test_data['Input']['Template']
      definiton = @test_data['Input']['Definition']
      allow(Defaults).to receive(:sections).and_return({ :env => "prod" })
      @dummy_class._process_kms_key(template: template, kms_key_definition: definiton, dr_account_id: '123123123', nonp_account_id: '123123124', environment: 'prod')
      expect(template).to eq @test_data['Output']['_process_kms_key_prod']
    end

    it 'template when enviorment is PROD' do
      template = @test_data['Input']['Template']
      definiton = @test_data['Input']['Definition']
      allow(Defaults).to receive(:sections).and_return({ :env => "PROD" })
      @dummy_class._process_kms_key(template: template, kms_key_definition: definiton, dr_account_id: '123123123', nonp_account_id: '123123124', environment: 'PROD')
      expect(template).to eq @test_data['Output']['_process_kms_key_prod']
    end

    it 'template when environment is NONP' do
      template = @test_data['Input']['Template']
      definiton = @test_data['Input']['Definition']
      allow(Defaults).to receive(:sections).and_return({ :env => "NONP" })
      @dummy_class._process_kms_key(template: template, kms_key_definition: definiton, dr_account_id: '123123123', nonp_account_id: '123123124', environment: 'NONP')
      expect(template).to eq @test_data['Output']['_process_kms_key']
    end

    it 'template when nonp_account_id variable is nil and environment nonp' do
      template = @test_data['Input']['Template']
      definiton = @test_data['Input']['Definition']
      allow(Defaults).to receive(:sections).and_return({ :env => "nonp" })
      @dummy_class._process_kms_key(template: template, kms_key_definition: definiton, dr_account_id: '123123123', nonp_account_id: '', environment: 'nonp')
      expect(template).to eq @test_data['Output']['_process_kms_key']
    end
  end
end # RSpec.describe
