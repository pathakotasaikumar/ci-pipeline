$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws/builders/util")
require "metadata_builder"

RSpec.describe MetadataBuilder do
  before(:context) do
  end

  context '.build' do
    it "raises error on both 'configSets' and 'config'" do
      expect {
        MetadataBuilder.build(
          user_metadata: {
            'AWS::CloudFormation::Init' => {
              "configSets" => {},
              "config" => {}
            }
          }
        )
      }.to raise_error(/Cannot specify both 'configSets' and 'config'/)

      expect {
        MetadataBuilder.build(
          user_metadata: {
            'AWS::CloudFormation::Init' => {
              "configSets" => {}
            }
          }
        )
      }.not_to raise_error

      expect {
        MetadataBuilder.build(
          user_metadata: {
            'AWS::CloudFormation::Init' => {
              "config" => {}
            }
          }
        )
      }.not_to raise_error
    end

    it "raises error on orphane user_prepare_config_set" do
      expect {
        MetadataBuilder.build(
          user_metadata: {
            'AWS::CloudFormation::Init' => {
              "configSets" => {
                "Prepare" => [
                  "cmd1",
                  "cmd2"
                ]
              }
            }
          }
        )
      }.to raise_error(/Cannot find referenced config key/)

      expect {
        MetadataBuilder.build(
          user_metadata: {
            'AWS::CloudFormation::Init' => {
              "cmd1" => [],
              "cmd2" => [],

              "configSets" => {
                "Prepare" => [
                  "cmd1",
                  "cmd2"
                ]
              }
            }
          }
        )
      }.not_to raise_error
    end

    def _test_action(action_section:, config_set:)
      actions = [
        "#{action_section}_cmd1",
        "#{action_section}_cmd2"
      ]

      case action_section
      when "PrePrepare"
        result = MetadataBuilder.build(pre_prepare: actions)
      when "PostPrepare"
        result = MetadataBuilder.build(post_prepare: actions)
      when "PreDeploy"
        result = MetadataBuilder.build(pre_deploy: actions)
      when "PostDeploy"
        result = MetadataBuilder.build(post_deploy: actions)
      end

      expect(result['AWS::CloudFormation::Init']['configSets'][config_set]).to include(action_section)
      expect(result['AWS::CloudFormation::Init'][action_section]).to eq(actions)
    end

    it "builds PrePrepare actions" do
      _test_action(config_set: 'Prepare', action_section: 'PrePrepare')
    end

    it "builds PostPrepare actions" do
      _test_action(config_set: 'Prepare', action_section: 'PostPrepare')
    end

    it "builds PreDeploy actions" do
      _test_action(config_set: 'Deploy', action_section: 'PreDeploy')
    end

    it "builds PreDeploy actions" do
      _test_action(config_set: 'Deploy', action_section: 'PostDeploy')
    end
  end
end # RSpec.describe
