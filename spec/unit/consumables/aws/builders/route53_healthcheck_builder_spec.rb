$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws/builders")
require "route53_healthcheck_builder"

RSpec.describe Route53HealthCheckBuilder do
  before(:context) do
    @dummy_class = DummyClass.new
    @dummy_class.extend(Route53HealthCheckBuilder)
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))
  end

  context '._process_route53_healthcheck' do
    it "updates template when valid inputs are passed on" do
      Context.component.set_variables(
        'api1', { 'UnhealthyAlarmName' => 'Alarm1234567890' }
      )

      template = @test_data["_process_route53_healthcheck"]["template"]
      healthchecks = @test_data["_process_route53_healthcheck"]["healthchecks"]

      expect {
        @dummy_class._process_route53_healthcheck(
          template: template,
          healthchecks: healthchecks
        )
      }.not_to raise_error

      expect(template).to eq(@test_data["_process_route53_healthcheck"]["result"][0])
    end
  end
end # RSpec.describe
