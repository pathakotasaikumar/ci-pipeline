$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws/builders")
require 'amq_broker_builder'
require_relative 'amq_broker_spec'

RSpec.describe AmqBrokerBuilder do
  include AmqBrokerSpec

  before(:context) do
    @dummy_class = DummyClass.new
    @dummy_class.extend(AmqBrokerBuilder)
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))['UnitTest']
  end

  context '_process_amq_broker_builder' do
    it 'should return template for single AZ deployment' do
      template = { 'Resources' => {}, 'Outputs' => {} }
      amq_template = @test_data["Input"]["Valid"]["SingleInstanceBroker"]['Configuration']

      @dummy_class._process_amq_broker_builder(
        template: template,
        component_name: 'amqbroker',
        amq_broker: amq_template,
        security_groups: ["sg-123"],
        amq_configuration: {
          amq_configuration_id: "amq-config-id",
          amq_configuration_revision: "1"
        },
        subnet_ids: ['subnet-123']
      )

      expect(template).to eq @test_data['Outputs']['single_instance']

      _validate_amq_login template, @test_data['Outputs']['single_instance']
    end

    it 'should return correct template for Multi AZ deployment' do
      template = { 'Resources' => {}, 'Outputs' => {} }
      amq_template = @test_data["Input"]["Valid"]["Broker"]['Configuration']

      @dummy_class._process_amq_broker_builder(
        template: template,
        component_name: 'amqbroker',
        amq_broker: amq_template,
        security_groups: ["sg-123"],
        amq_configuration: {
          amq_configuration_id: "amq-config-id",
          amq_configuration_revision: "1"
        },
        subnet_ids: ['subnet-123', 'subnet-456']
      )

      expect(template).to eq @test_data['Outputs']['Broker']

      _validate_amq_login template, @test_data['Outputs']['single_instance']
    end
  end

  context '_subnet_ids' do
    it 'should return single subnet for single_instance deployment type' do
      deployment_mode = 'SINGLE_INSTANCE'
      subnet_value = %w[
        'subnet-1234'
        'subnet-456'
      ]
      allow(Context).to receive_message_chain('environment.subnet_ids').and_return(subnet_value)
      subnet_alias = '@private'

      subnet_id = @dummy_class._subnet_ids(
        deployment_mode: deployment_mode,
        subnet_alias: subnet_alias
      )
      expect(subnet_id).to be_a(Array)
      expect((subnet_id).count).to be == 1
    end

    it 'should return single subnet for single_instance deployment type' do
      deployment_mode = 'ACTIVE_STANDBY_MULTI_AZ'
      subnet_value = %w[
        'subnet-1234'
        'subnet-456'
      ]
      allow(Context).to receive_message_chain('environment.subnet_ids').and_return(subnet_value)
      subnet_alias = '@private'

      subnet_id = @dummy_class._subnet_ids(
        deployment_mode: deployment_mode,
        subnet_alias: subnet_alias
      )
      expect(subnet_id).to be_a(Array)
      expect((subnet_id).count).to be == 2
    end

    it 'raise exception if Invalid deployment type is provided' do
      deployment_mode = 'ACTIVE_STANDBY_MULTI_AZ_SINGLE_AZ'
      subnet_value = %w[
        'subnet-1234'
        'subnet-456'
      ]
      allow(Context).to receive_message_chain('environment.subnet_ids').and_return(subnet_value)
      subnet_alias = '@private'

      expect {
        @dummy_class._subnet_ids(
          deployment_mode: deployment_mode,
          subnet_alias: subnet_alias
        )
      } .to raise_error(RuntimeError, /Invalid Deployment Mode selected for/)
    end
  end

  context '._process_amq_admin_password' do
    it 'should decrypt master amq password' do
      users_definition = {
        "Username" => 'test',
        "Password" => 'encryptedpassword',
        "ConsoleAccess" => true
      }

      allow(AwsHelper).to receive(:kms_decrypt_data)

      expect {
        @dummy_class._process_amq_admin_password(
          user_definition: users_definition
        )
      }.not_to raise_error
    end

    it 'should raise KMS Decrypt exception' do
      users_definition = {
        "Username" => 'test',
        "Password" => 'encryptedpassword',
        "ConsoleAccess" => true
      }

      allow(AwsHelper).to receive(:kms_decrypt_data).and_raise(ActionError)

      expect {
        @dummy_class._process_amq_admin_password(
          user_definition: users_definition
        )
      }.to raise_error(RuntimeError, /Failed to decrypt the AMQ admin password/)
    end
  end
end
