$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib"))
require 'action.rb'
require 'consumable.rb'
require 'consumables/aws/aws_instance.rb'

RSpec.describe Action do
  context '.instantiate' do
    it 'fails on empty name' do
      expect {
        Action.instantiate()
      }.to raise_error(/must be specified/)
    end

    it 'raises error on unknown action' do
      expect {
        Action.instantiate(
          name: "RandomAction42"
        )
      }.to raise_error(/Unknown action/)
    end

    it 'creates actions' do
      allow(Context).to receive_message_chain("environment.variable")
        .with('shared_accounts', [])
        .and_return(["123456789012, 123456789013"])

      actions = {
        "AddLaunchPermission" => {
          :stage => 'PostDeploy',
          :component => (
            component = double(Consumable)
            allow(component).to receive(:type) .and_return("aws/image")
            component
          ),
          :params => {}
        },

        "ExecuteStateMachine" => {
          :stage => 'PostDeploy',
          :component => (
            component = double(Consumable)
            allow(component).to receive(:type) .and_return("aws/state-machine")
            component
          ),
          :params => { "StateMachineName" => 'my-machine' }
        },

        "HTTPRequest" => {
          :stage => :all,
          :component => (
            component = double(Consumable)
            allow(component).to receive(:type) .and_return("aws/state-machine")
            component
          ),
          :params => { "URL" => 'http://localhost' }
        },

        "InvokeLambda" => {
          :stage => "PostDeploy",
          :component => (
            component = double(Consumable)
            allow(component).to receive(:type) .and_return("aws/lambda")
            component
          ),
          :params => {}
        },

        "RegisterApi" => {
          :stage => :all,
          :component => (
            component = double(Consumable)

            allow(component).to receive(:type) .and_return(:all)

            allow(Context).to receive_message_chain("environment.variable")
                              .with('api_gateway_admin_url_nonp', nil)
                              .and_return('http://localhost')

            allow(Context).to receive_message_chain("environment.variable")
                              .with('api_gateway_custom_key', nil)
                              .and_return('http://localhost')

            allow(Context).to receive_message_chain("environment.variable")
                              .with('api_gateway_username', nil)
                              .and_return('api_user')

            allow(Context).to receive_message_chain("environment.variable")
                              .with('api_gateway_password', nil)
                              .and_return('api_password')

            component
          ),
          :params => {
            "Basepath" => "api",
            "Swagger" => "swagger",
            "ApiConf" => "api_config"
          }
        },

        "QualysWAS" => {
          :stage => 'PostDeploy',
          :component => (
            component = double(Consumable)
            allow(component).to receive(:type) .and_return(:all)
            component
          ),
          :params => {
            "ScanConf" => { "qualys_was" => 'dummy' }
          }
        },

        "SetDesiredCapacity" => {
          :stage => "PostDeploy",
          :component => (
            component = double(Consumable)
            allow(component).to receive(:type) .and_return("aws/autoscale")
            component
          ),
          :params => {
            "MinSize" => 1,
            "MaxSize" => 2
          }
        },

        "Snapshot" => {
          :stage => "PostDeploy",
          :component => (
            component = double(Consumable)
            allow(component).to receive(:type) .and_return("aws/volume")
            component
          ),
          :params => {

          }
        },

        "SetWeightRoutePolicy" => {
          :stage => "PostDeploy",
          :component => (
            component = double(Consumable)
            allow(component).to receive(:type) .and_return("aws/route53")
            component
          ),
          :params => {
            "Weight" => 1,
            "RecordSet" => "record_set"
          }
        }

      }

      actions.keys.each do |action|
        action = Action.instantiate(
          name: action,
          component: actions[action][:component],
          stage: actions[action][:stage],
          params: actions[action][:params]
        )
      end
    end
  end

  context '.valid_stages' do
    class InvalidStagesAction < Action
      def valid_components
        %w(
          aws/state-machine
        )
      end
    end

    it 'requires override' do
      expect {
        action = InvalidStagesAction.new
        action.valid_stages
      }.to raise_error(/Must override method 'valid_stages'/)
    end
  end

  context '.valid_components' do
    class InvalidComponentsAction < Action
      def valid_stages
        [:all]
      end
    end

    it 'requires override' do
      expect {
        component = double(Consumable)
        allow(component).to receive(:type) .and_return("aws/lambda")

        action = InvalidComponentsAction.new(component: component)
        action.valid_components
      }.to raise_error(/Must override method 'valid_components'/)
    end
  end

  context '.invoke' do
    class InvalidInvokeAction < Action
      def valid_components
        [:all]
      end

      def valid_stages
        [:all]
      end
    end

    it 'requires override' do
      expect {
        component = double(Consumable)
        allow(component).to receive(:type) .and_return("aws/lambda")

        action = InvalidInvokeAction.new(component: component)
        action.invoke
      }.to raise_error(/Must override method 'invoke'/)
    end
  end

  context '.name' do
    class NamedAction < Action
      def valid_components
        [:all]
      end

      def valid_stages
        [:all]
      end
    end

    it 'returns action name' do
      component = double(Consumable)
      allow(component).to receive(:type) .and_return("aws/lambda")

      action = NamedAction.new(component: component)
      expect(action.name).to eq(action.class.name)
    end
  end
end # RSpec.describe
