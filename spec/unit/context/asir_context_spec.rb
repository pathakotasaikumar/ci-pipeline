$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib/context/"))
$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib/context/storage"))
require 'asir_context.rb'
require 's3_state_storage.rb'
RSpec.describe AsirContext do
  before(:context) do
  end

  context '.set_name' do
    it 'sets name' do
      dummy_storage = double(Object)
      sections = {
        env: 'prod',
        ams: 'ams01',
        qda: 'c031',
        as: '01',
        branch: 'master',
        ase: 'dev',
        build: '05'
      }
      asir = AsirContext.new(dummy_storage, sections)
      asir.set_name = "test-name"

      expect(asir.set_name).to eq("test-name")
    end
  end

  context '.destination_stack_id' do
    it 'returns stack id' do
      dummy_storage = double(Object)
      sections = {
        env: 'prod',
        ams: 'ams01',
        qda: 'c031',
        as: '01',
        branch: 'master',
        ase: 'dev',
        build: '05'
      }

      allow(dummy_storage).to receive(:load)
      allow(dummy_storage).to receive(:save)

      asir = AsirContext.new(dummy_storage, sections)

      asir.set_destination_details(
        'test-stack',
        'security-group-id'
      )

      expect(asir.destination_stack_id).to eq("test-stack")
    end
  end

  context '.destination_account_id' do
    it 'returns nil for nil stack' do
      dummy_storage = double(Object)
      sections = {
        env: 'prod',
        ams: 'ams01',
        qda: 'c031',
        as: '01',
        branch: 'master',
        ase: 'dev',
        build: '05'
      }

      allow(dummy_storage).to receive(:load)
      allow(dummy_storage).to receive(:save)

      asir = AsirContext.new(dummy_storage, sections)

      expect(asir.destination_account_id).to eq(nil)
    end

    it 'returns [:4] item from stack id' do
      dummy_storage = double(Object)
      sections = {
        env: 'prod',
        ams: 'ams01',
        qda: 'c031',
        as: '01',
        branch: 'master',
        ase: 'dev',
        build: '05'
      }

      allow(dummy_storage).to receive(:load)
      allow(dummy_storage).to receive(:save)

      asir = AsirContext.new(dummy_storage, sections)

      asir.set_destination_details(
        '11:22:33:44:55',
        'security-group-id'
      )

      expect(asir.destination_account_id).to eq("55")
    end

    context '.destination_rules_template' do
      it 'returns Template section' do
        dummy_storage = double(Object)
        sections = {
          env: 'prod',
          ams: 'ams01',
          qda: 'c031',
          as: '01',
          branch: 'master',
          ase: 'dev',
          build: '05'
        }

        allow(dummy_storage).to receive(:save)
        allow(dummy_storage).to receive(:load) .and_return({
          "Template" => "11-22"
        })

        asir = AsirContext.new(dummy_storage, sections)
        expect(asir.destination_rules_template).to eq("11-22")
      end
    end

    context '.source_stack_id' do
      it 'returns source stack id' do
        dummy_storage = double(Object)
        sections = {
          env: 'prod',
          ams: 'ams01',
          qda: 'c031',
          as: '01',
          branch: 'master',
          ase: 'dev',
          build: '05'
        }

        allow(dummy_storage).to receive(:save)
        allow(dummy_storage).to receive(:load) .and_return({
          "AwsAccountId" => "account-id"
        })

        asir = AsirContext.new(dummy_storage, sections)
        expect(asir.source_stack_id).to eq("account-id")
      end
    end

    context '.source_account_id' do
      it 'returns nil source account id' do
        dummy_storage = double(Object)
        sections = {
          env: 'prod',
          ams: 'ams01',
          qda: 'c031',
          as: '01',
          branch: 'master',
          ase: 'dev',
          build: '05'
        }

        allow(dummy_storage).to receive(:save)
        allow(dummy_storage).to receive(:load)

        asir = AsirContext.new(dummy_storage, sections)
        expect(asir.source_account_id).to eq(nil)
      end

      it 'returns source account id' do
        dummy_storage = double(Object)
        sections = {
          env: 'prod',
          ams: 'ams01',
          qda: 'c031',
          as: '01',
          branch: 'master',
          ase: 'dev',
          build: '05'
        }

        allow(dummy_storage).to receive(:save)
        allow(dummy_storage).to receive(:load) .and_return ( {
          "StackId" => "11:22:33:44:55"
        })

        asir = AsirContext.new(dummy_storage, sections)
        expect(asir.source_account_id).to eq("55")
      end
    end
  end
end # RSpec.describe
