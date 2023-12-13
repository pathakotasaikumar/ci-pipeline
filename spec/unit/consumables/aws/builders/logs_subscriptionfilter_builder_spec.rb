$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws/builders")
require "logs_subscriptionfilter_builder"

RSpec.describe LogsSubscriptionFilterBuilder do
  before(:context) do
    @dummy_class = DummyClass.new
    @dummy_class.extend(LogsSubscriptionFilterBuilder)
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))

    Context.component.set_variables('logger', {
      'DestinationArn' => 'logger-arn',
    })
  end

  context "._process_logs_subscription_filter" do
    it 'successfully builds template' do
      @test_data['_process_logs_subscription_filter']['Input'].each_with_index do |definition, index|
        template = { "Resources" => {}, "Outputs" => {} }
        allow(Defaults).to receive(:txt_by_dns).and_return('dummy-arn')
        expect {
          @dummy_class._process_logs_subscription_filter(
            template: template,
            log_group: 'dummy-log-group',
            definitions: definition
          )
        }.not_to raise_error

        expect(template).to eq @test_data['_process_logs_subscription_filter']['Output'][index]
      end
    end
  end
end
