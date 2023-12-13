$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib/util"))
require 'yaml'

RSpec.describe AwsHelperClass do
  before(:all) {
    @aws_helper = AwsHelper

    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/aws_helper_class_spec.yaml"))
    @tags = []

    # EC2 method tests
    @stack_trail = "#{ENV['bamboo_planRepository_branchName']}-#{ENV['bamboo_buildNumber']}-#{ENV['bamboo_planRepository_planKey']}"
    @ec2_stack_name = "TestAwsHelperEC2CloudFormationStack-#{@stack_trail}".gsub(/[^a-zA-Z0-9\-]/, '')
    @ec2_ami_name = "TestAwsHelperEC2AMI-#{@stack_trail}".gsub(/[^a-zA-Z0-9\-]/, '')

    @ec2_template = @test_data["Ec2"]["Template"]
    @ec2_template["Resources"]["myEC2Instance"]["Properties"]["ImageId"] = ENV['bamboo_soe_ami']
    @ec2_template["Resources"]["myEC2Instance"]["Properties"]["SubnetId"] = ENV["bamboo_aws_subnets"].split(',').first

    @ec2_state = {}
  }

  context 'AMI method' do
    it '.cfn_create_stack creates a new EC2 stack' do
      expect {
        begin
          Log.debug "@ec2_stack_name:#{@ec2_stack_name} | @ec2_template #{@ec2_template} | @tags #{@tags}}"
          outputs = @aws_helper.cfn_create_stack(stack_name: @ec2_stack_name, template: @ec2_template, tags: @tags)
          @ec2_state.merge!(outputs)
        rescue ActionError => e
          @ec2_state.merge!(e.partial_outputs)
          raise
        end
      }.not_to raise_error

      expect(@ec2_state["StackId"]).not_to be_nil
      expect(@ec2_state["StackName"]).to eql(@ec2_stack_name)
      expect(@ec2_state["EC2InstanceId"]).not_to be_nil
    end

    it '.ec2_shutdown_instance_and_create_image creates an image from an EC2 instance' do
      pending("EC2 stack create failed") if @ec2_state['StackId'].nil?

      expect {
        begin
          outputs = @aws_helper.ec2_shutdown_instance_and_create_image(@ec2_state['EC2InstanceId'], @ec2_ami_name)
          @ec2_state.merge!(outputs)
        rescue ActionError => e
          @ec2_state.merge!(e.partial_outputs)
          raise
        end
      }.not_to raise_error

      expect(@ec2_state["ImageId"]).not_to be_nil
      expect(@ec2_state["ImageName"]).to eql(@ec2_ami_name)
    end

    it '.ec2_delete_image deletes an existing AMI' do
      pending("image create failed") if @ec2_state['ImageId'].nil?

      expect {
        @aws_helper.ec2_delete_image(@ec2_state['ImageId'])
      }.not_to raise_error
    end

    it '.cfn_delete_stack deletes the EC2 stack' do
      pending("EC2 stack create failed") if @ec2_state['StackId'].nil?

      expect {
        @aws_helper.cfn_delete_stack(@ec2_state['StackId'])
      }.not_to raise_error
    end
  end
end
