$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws/builders")
require 'security_item_builder.rb'

RSpec.describe SecurityItemBuilder do
  security_items = [
    {
      "Name" => "ElbSecurityGroup",
      "Type" => "SecurityGroup",
      "Component" => "my-apptier",
    },
    {
      "Name" => "AsgSecurityGroup",
      "Type" => "SecurityGroup",
      "Component" => "my-apptier",
    },
    {
      "Name" => "InstanceRole",
      "Type" => "Role",
      "Component" => "my-apptier",
      "ManagedPolicyArns" => "arn:aws:iam::policy/my-managed-policy",
    }
  ]

  expected_item_template = {
    "Resources" => {
      "ElbSecurityGroup" => {
        "Type" => "AWS::EC2::SecurityGroup",
        "Properties" => {
          "VpcId" => "vpc-12345678"
        }
      },
      "AsgSecurityGroup" => {
        "Type" => "AWS::EC2::SecurityGroup",
        "Properties" => {
          "VpcId" => "vpc-12345678"
        }
      },
      "InstanceRole" => {
        "Type" => "AWS::IAM::Role",
        "Properties" => {
          "AssumeRolePolicyDocument" => {
            "Version" => "2012-10-17",
            "Statement" => [
              {
                "Effect" => "Allow",
                "Principal" => {
                  "Service" => [
                    "ec2.amazonaws.com"
                  ]
                },
                "Action" => [
                  "sts:AssumeRole"
                ]
              }
            ]
          },
          "ManagedPolicyArns" => ["arn:aws:iam::policy/my-managed-policy"],
          "Path" => "/",
          "PermissionsBoundary" => { "Fn::Sub" => "arn:aws:iam::${AWS::AccountId}:policy/PermissionBoundaryPolicy" },
        }
      }
    },
    "Outputs" => {
      "ElbSecurityGroupId" => {
        "Description" => "Id for security group ElbSecurityGroup",
        "Value" => {
          "Fn::GetAtt" => [
            "ElbSecurityGroup",
            "GroupId"
          ]
        }
      },
      "AsgSecurityGroupId" => {
        "Description" => "Id for security group AsgSecurityGroup",
        "Value" => {
          "Fn::GetAtt" => [
            "AsgSecurityGroup",
            "GroupId"
          ]
        }
      },
      "InstanceRoleArn" => {
        "Description" => "Arn for role InstanceRole",
        "Value" => {
          "Fn::GetAtt" => ["InstanceRole", "Arn"],
        }
      }
    }
  }

  def compare_hash(path, expected, actual)
    expect("#{path} class = #{actual.class}").to eq("#{path} class = #{expected.class}")

    expected.each do |key, value|
      if value.is_a? Hash
        compare_hash("#{path}.#{key}", value, actual[key])
      else
        expect("#{path}.#{key} = #{actual[key]}").to eq("#{path}.#{key} = #{value}")
      end
    end
  end

  before(:context) do
    @dummy_class = DummyClass.new
    @dummy_class.extend(SecurityItemBuilder)
  end

  context '.process_security_items' do
    it 'correctly generates security items CloudFormation template' do
      template = { 'Resources' => {}, 'Outputs' => {} }
      @dummy_class._process_security_items(
        template: template,
        vpc_id: "vpc-12345678",
        security_items: security_items
      )

      compare_hash("", expected_item_template, template)
    end
  end

  context '._process_security_items' do
    it 'logs error on unknown security type' do
      # this also need to ensure that error is logged
      allow(Log).to receive(:error)

      expect {
        @dummy_class._process_security_items(
          template: '',
          vpc_id: '',
          security_items: [
            {
              'Type' => 'custom-type'
            }
          ]
        )
      }.to_not raise_error
    end
  end
end
