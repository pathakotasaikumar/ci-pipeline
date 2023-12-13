$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws/builders")
require "sns_factory_builder"
require "yaml"

RSpec.describe SnsFactoryBuilder do
  before(:context) do
    @dummy_class = DummyClass.new
    @dummy_class.extend(SnsFactoryBuilder)
    @test_data = YAML.load(
      File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"),
      permitted_classes: ['IamSecurityRule']
    )
  end

  context "._delete_topics_lambda_security_rules" do
    it "updates template when valid inputs are passed on" do
      security_rule = @dummy_class._delete_topics_lambda_security_rules(
        component_name: 'SnsFactory',
        execution_role_name: 'LambdaExecutionRole',
        prefix_arn: 'arn:aws:sns:ap-southeast-2:123456789012:ams01-c031-99-dev-master-5-SnsFactory'
      )

      expect(security_rule).to eq @test_data["SnsFactory"]["SecurityRules"]
    end
  end

  context "._process_sns_factory" do
    it "updates template when valid inputs are passed on" do
      template = @test_data["SnsFactory"]["Template"]
      result_template = @dummy_class._process_sns_factory(
        template: template,
        prefix: "ams01-p292-01-dev-master-1-testsnsfactory",
        execution_role_arn: 'arn:aws:iam::123456789012:role/ams01-c031-99-dev-master-5-SnsFactory-LambdaExecutionRole'
      )

      filepath = "#{BASE_DIR}/lib/consumables/aws/aws_sns_factory/"
      filename = "lambda_delete_topics.py"
      lambda_function_file = File.open(File.join(filepath, filename))

      join_array = []
      File.readlines(lambda_function_file).each { |line| join_array.push(line) }
      source_code = { 'Fn::Join' => ['', join_array] }

      lambda_code = result_template["Resources"]["SNSFactoryCustomResourceLambda"]["Properties"]["Code"]["ZipFile"]

      expect(lambda_code).to eq source_code

      result_template["Resources"]["SNSFactoryCustomResourceLambda"]["Properties"]["Code"]["ZipFile"] = nil

      expect(result_template).to eq @test_data["SnsFactory"]["Output"]
    end
  end
end # RSpec.describe
