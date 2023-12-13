$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws/builders")
require "route53_record_builder"

RSpec.describe Route53RecordBuilder do
  before(:context) do
    @dummy_class = DummyClass.new
    @dummy_class.extend(Route53RecordBuilder)
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))
  end

  context '._process_route53_records' do
    it "updates template when valid inputs are passed on" do
      Context.component.set_variables(
        'api1', { 'DeployDnsName' => 'www.google.com' }
      )

      template = @test_data["_process_route53_records"]["template"]
      record_sets = @test_data["_process_route53_records"]["record_sets"]

      expect {
        @dummy_class._process_route53_records(
          template: template,
          record_name: 'test.ams01.nonp.aws.qcp',
          record_sets: record_sets
        )
      }.not_to raise_error

      expect(template).to eq(@test_data["_process_route53_records"]["result"][0])
    end
  end
end # RSpec.describe
