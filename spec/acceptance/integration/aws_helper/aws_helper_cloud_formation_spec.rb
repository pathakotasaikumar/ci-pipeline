$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib/util"))
require 'yaml'

RSpec.describe AwsHelperClass do
  before(:all) {
    @aws_helper = AwsHelper

    # CloudFormation method tests
    @stack_trail = "#{ENV['bamboo_planRepository_branchName']}-#{ENV['bamboo_buildNumber']}-#{ENV['bamboo_planRepository_planKey']}"
    @stack_name = "TestAwsHelperCloudFormationStack-#{@stack_trail}".gsub(/[^a-zA-Z0-9\-]/, '')
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/aws_helper_class_spec.yaml"))

    @template = @test_data["CloudFormation"]["Template"]
    @updated_template = @test_data["CloudFormation"]["UdpatedTemplate"]
    @bad_template = @test_data["CloudFormation"]["BadTemplate"]

    @tags = []
    @cfn_state = {}
  }

  context 'CloudFormation method' do
    it '.cfn_create_stack creates a new stack' do
      expect {
        begin
          outputs = @aws_helper.cfn_create_stack(stack_name: @stack_name, template: @template, tags: @tags)
          @cfn_state.merge!(outputs)
        rescue ActionError => e
          @cfn_state.merge!(e.partial_outputs)
          raise
        end
      }.not_to raise_error

      expect(@cfn_state["StackId"]).not_to be_nil
      expect(@cfn_state["StackName"]).to eql(@stack_name)
      expect(@cfn_state["WaitConditionId"]).not_to be_nil
    end

    it '.cfn_update_stack updates an existing stack' do
      pending("stack create failed") if @cfn_state['StackId'].nil?

      expect {
        outputs = @aws_helper.cfn_update_stack(stack_name: @cfn_state['StackId'], template: @updated_template, tags: @tags)
        @cfn_state.merge!(outputs)
      }.not_to raise_error

      expect(@cfn_state["StackId"]).to eql(@cfn_state['StackId'])
      expect(@cfn_state["StackName"]).to eql(@stack_name)
      expect(@cfn_state["WaitCondition2Id"]).not_to be_nil
      expect(@cfn_state["WaitCondition2Id"]).not_to eql(@wait_condition_id)
    end

    it '.cfn_update_stack fails to update a stack with a bad template', :skip => true do
      pending("stack create failed") if @cfn_state['StackId'].nil?

      expect {
        @aws_helper.cfn_update_stack(stack_name: @cfn_state['StackId'], template: @bad_template, tags: @tags)
      }.to raise_error(ActionError)
    end

    it '.cfn_delete_stack deletes a stack' do
      pending("stack create failed") if @cfn_state['StackId'].nil?

      expect {
        @aws_helper.cfn_delete_stack(@cfn_state['StackId'])
      }.not_to raise_error
    end
  end
end
