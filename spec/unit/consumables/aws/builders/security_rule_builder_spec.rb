$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws/builders")
require 'security_rule_builder.rb'

RSpec.describe SecurityRuleBuilder do
  sections = {
    ams: "ams99",
    qda: "c999",
    as: "99",
    ase: "dev",
    ase_number: 123,
    plan_key: "ams99-c999s99dev",
    branch: "master",
    build: "1",
    env: "nonp",
    asbp_type: "qda",
  }

  security_rules = [
    # Simple linking
    IpSecurityRule.new(
      sources: "my-webtier.AsgSecurityGroup",
      destination: "my-apptier.ElbSecurityGroup",
      ports: [
        "TCP:80-81",
        "TCP:443"
      ]
    ),
    # Circular linking
    IpSecurityRule.new(
      sources: "my-apptier.AsgSecurityGroup",
      destination: "my-apptier.AsgSecurityGroup",
      ports: [
        "UDP:2000"
      ]
    ),
    # IAM linking
    IamSecurityRule.new(
      roles: "my-apptier.InstanceRole",
      resources: "arn:aws:sqs:ap-southeast-2:756536494181:test-queue-arn-Queue-1485JSQFS29Q",
      actions: ["sqs:PutMessage", "sqs:GetMessage"]
    ),
  ]

  expected_rule_template = {
    "Resources" => {
      "myxwebtierxAsgSecurityGroupOnTCPx80x81" => {
        "Type" => "AWS::EC2::SecurityGroupIngress",
        "Properties" => {
          "SourceSecurityGroupId" => "sg-web-asg",
          "GroupId" => "sg-app-elb",
          "IpProtocol" => "tcp",
          "FromPort" => "80",
          "ToPort" => "81"
        }
      },
      "myxwebtierxAsgSecurityGroupOnTCPx443" => {
        "Type" => "AWS::EC2::SecurityGroupIngress",
        "Properties" => {
          "SourceSecurityGroupId" => "sg-web-asg",
          "GroupId" => "sg-app-elb",
          "IpProtocol" => "tcp",
          "FromPort" => "443",
          "ToPort" => "443"
        }
      },
      "myxapptierxAsgSecurityGroupOnUDPx2000" => {
        "Type" => "AWS::EC2::SecurityGroupIngress",
        "Properties" => {
          "SourceSecurityGroupId" => "sg-app-asg",
          "GroupId" => "sg-app-asg",
          "IpProtocol" => "udp",
          "FromPort" => "2000",
          "ToPort" => "2000"
        }
      },
      "myxapptierxInstanceRolexmyxqueuePolicy" => {
        "Type" => "AWS::IAM::Policy",
        "Properties" => {
          "PolicyName" => "ams99-c999-99-dev-master-1-my-queue",
          "PolicyDocument" => {
            "Version" => "2012-10-17",
            "Statement" => [
              {
                "Effect" => "Allow",
                "Action" => [
                  "sqs:PutMessage",
                  "sqs:GetMessage",
                ],
                "Resource" => ["arn:aws:sqs:ap-southeast-2:756536494181:test-queue-arn-Queue-1485JSQFS29Q"],
              }
            ]
          },
          "Roles" => [
            "ams99-c001-01-dev-master-1-app-InstanceRole-1BYMM7M4RPVEE",
          ]
        }
      }
    }
  }

  Context.environment.set_variables({ 'aws_vpc_id' => 'vpc-12345678' })
  Context.component.set_security_details("my-apptier", "stack-123", { 'AsgSecurityGroupId' => 'sg-app-asg', 'ElbSecurityGroupId' => 'sg-app-elb', 'InstanceRoleArn' => 'ams99-c001-01-dev-master-1-app-InstanceRole-1BYMM7M4RPVEE' })
  Context.component.set_security_details("my-webtier", "stack-123", { 'AsgSecurityGroupId' => 'sg-web-asg', 'ElbSecurityGroupId' => 'sg-web-elb', 'InstanceRoleArn' => 'ams99-c001-01-dev-master-1-web-InstanceRole-1BYMM7M4RPVEE' })

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
    @dummy_class.extend(SecurityRuleBuilder)
  end

  context '._parse_port_specification' do
    it 'does something', :skip => true do
      # Test single-port on all protocols
      expect(@dummy_class._parse_port_specification("TCP:80")).to eq({ protocol: 'tcp', from_port: '80', to_port: '80' })
      expect(@dummy_class._port_details("UDP:80")).to eq({ protocol: 'udp', from_port: '80', to_port: '80' })
      expect(@dummy_class._port_details("ALL:80")).to eq({ protocol: '-1', from_port: '80', to_port: '80' })

      # Test port range
      expect(@dummy_class._port_details("TCP:80-81")).to eq({ protocol: 'tcp', from_port: '80', to_port: '81' })
      expect(@dummy_class._port_details("TCP:80-81")).to eq({ protocol: 'tcp', from_port: '80', to_port: '81' })

      # Test port wildcard
      expect(@dummy_class._port_details("ALL:*")).to eq({ protocol: '-1', from_port: '0', to_port: '65535' })
      expect(@dummy_class._port_details("TCP:*-1000")).to eq({ protocol: 'tcp', from_port: '0', to_port: '1000' })
      expect(@dummy_class._port_details("TCP:1000-*")).to eq({ protocol: 'tcp', from_port: '1000', to_port: '65535' })

      # Test invalid protocol
      expect { @dummy_class._port_details("ABC:80") }.to raise_error(ArgumentError)

      # Test invalid port spec
      expect { @dummy_class._port_details("TCP:80,82") }.to raise_error(ArgumentError)

      # Test invalid port range
      expect { @dummy_class._port_details("TCP:81-80") }.to raise_error(ArgumentError)
    end
  end

  context '.process_security_rules' do
    it 'correctly generates security rules CloudFormation template' do
      allow(Defaults).to receive(:sections).and_return(sections)

      template = { 'Resources' => {} }
      @dummy_class._process_security_rules(
        template: template,
        rules: security_rules,
        component_name: "my-queue",
      )

      compare_hash("", expected_rule_template, template)
    end
  end

  context '._process_security_items' do
    it 'raises error on unknown security rule type' do
      expect {
        @dummy_class._process_security_rules(
          template: '',
          rules: ['custom-rule'],
          component_name: '',
          skip_non_existant: false
        )
      }.to raise_error(/Unknown security rule type/)
    end
  end

  context '._build_policies' do
    it 'raises error on missing IAM role' do
      allow(Context).to receive_message_chain('component.role_name')
        .and_return(nil)

      expect {
        @dummy_class._build_policies(
          template: '',
          policy_statements: {
            'my-component.my-policy' => {

            }
          },
          component_name: '',
          skip_non_existant: false
        )
      }.to raise_error(/Cannot find IAM role/)
    end
  end

  context '._build_ip_rule' do
    it 'builds sg- group' do
      rule = double(Object)

      allow(rule).to receive(:destination).and_return('sg-component-1')
      allow(rule).to receive(:ports).and_return(['80', '81'])
      allow(rule).to receive(:sources).and_return([])

      @dummy_class._build_ip_rule(
        template: nil,
        rule: rule,
        skip_non_existant: false
      )
    end

    it 'raises error on null sources if skip_non_existant = false' do
      rule = double(Object)

      allow(rule).to receive(:destination).and_return('sg-component-1')
      allow(rule).to receive(:ports).and_return(['80', '81'])
      allow(rule).to receive(:sources).and_return(nil)

      expect {
        @dummy_class._build_ip_rule(
          template: nil,
          rule: rule,
          skip_non_existant: false
        )
      }.to raise_error(/IP rule source could not be resolved/)
    end

    it 'raises error on null non-sg groups if skip_non_existant = false' do
      rule = double(Object)

      allow(rule).to receive(:destination).and_return('sg1-component-1')
      allow(rule).to receive(:ports).and_return(['80', '81'])
      allow(rule).to receive(:sources).and_return(nil)

      allow(Context).to receive_message_chain('component.sg_id').and_return(nil)

      expect {
        @dummy_class._build_ip_rule(
          template: nil,
          rule: rule,
          skip_non_existant: false
        )
      }.to raise_error(/Cannot find destination security group/)
    end

    it 'builds SecurityGroupIngress resource' do
      rule = double(Object)

      allow(rule).to receive(:destination).and_return('sg1-component-1')
      allow(rule).to receive(:ports).and_return([IpPort.from_specification('tcp:90-91')])
      allow(rule).to receive(:name).and_return('custom-rule')
      allow(rule).to receive(:sources).and_return(['192.168.2.0/24'])
      allow(Context).to receive_message_chain('component.sg_id').and_return('dst-group')

      template = {
        "Resources" => {}
      }

      result = @dummy_class._build_ip_rule(
        template: template,
        rule: rule,
        skip_non_existant: false
      )

      expect(template["Resources"]["customxrule"]).to eq({
        'Type' => 'AWS::EC2::SecurityGroupIngress',
        'Properties' => {
          'CidrIp' => '192.168.2.0/24',
          'GroupId' => 'dst-group',
          'IpProtocol' => 'tcp',
          'FromPort' => '90',
          'ToPort' => '91'
        }
      })
    end

    it 'builds sg- resource' do
      rule = double(Object)

      allow(rule).to receive(:destination).and_return('sg1-component-1')
      allow(rule).to receive(:ports).and_return([IpPort.from_specification('tcp:90-91')])
      allow(rule).to receive(:name).and_return('custom-rule')
      allow(rule).to receive(:sources).and_return(['sg-group-1'])
      allow(Context).to receive_message_chain('component.sg_id').and_return('dst-group')

      template = {
        "Resources" => {}
      }

      result = @dummy_class._build_ip_rule(
        template: template,
        rule: rule,
        skip_non_existant: false
      )

      expect(template["Resources"]["customxrule"]).to eq({
        'Type' => 'AWS::EC2::SecurityGroupIngress',
        'Properties' => {
          'SourceSecurityGroupId' => 'sg-group-1',
          'GroupId' => 'dst-group',
          'IpProtocol' => 'tcp',
          'FromPort' => '90',
          'ToPort' => '91'
        }
      })
    end

    it 'builds @- resource' do
      rule = double(Object)

      allow(rule).to receive(:sources).and_return(['src-component-1.src-security-group'])
      allow(rule).to receive(:destination).and_return('@dst-component-1.dst-security-group')

      allow(rule).to receive(:ports).and_return([IpPort.from_specification('tcp:90-91')])
      allow(rule).to receive(:name).and_return('custom-rule')

      allow(Context).to receive_message_chain('component.sg_id').with('src-component-1', 'src-security-group').and_return('src-group-resolved')
      allow(Context).to receive_message_chain('component.sg_id').with('dst-component-1', 'dst-security-group').and_return('dst-group-resolved')

      template = {
        "Resources" => {}
      }

      result = @dummy_class._build_ip_rule(
        template: template,
        rule: rule,
        skip_non_existant: false
      )

      expect(template["Resources"]["customxrule"]).to eq({
        'Type' => 'AWS::EC2::SecurityGroupIngress',
        'Properties' => {
          'SourceSecurityGroupId' => 'src-group-resolved',
          'GroupId' => 'dst-group-resolved',
          'IpProtocol' => 'tcp',
          'FromPort' => '90',
          'ToPort' => '91'
        }
      })
    end

    it 'builds @- resource and fails on non-existing source group' do
      rule = double(Object)

      allow(rule).to receive(:sources).and_return(['src-component-1.src-security-group'])
      allow(rule).to receive(:destination).and_return('@dst-component-1.dst-security-group')

      allow(rule).to receive(:ports).and_return([IpPort.from_specification('tcp:90-91')])
      allow(rule).to receive(:name).and_return('custom-rule')

      allow(Context).to receive_message_chain('component.sg_id').with('src-component-1', 'src-security-group').and_return(nil)
      allow(Context).to receive_message_chain('component.sg_id').with('dst-component-1', 'dst-security-group').and_return('dst-group-resolved')

      template = {
        "Resources" => {}
      }

      expect {
        result = @dummy_class._build_ip_rule(
          template: template,
          rule: rule,
          skip_non_existant: false
        )
      }.to raise_error(/Cannot find source security group/)
    end
  end

  context '._build_policy_statement' do
    it 'handles resources correctly' do
      rule = double(Object)

      allow(rule).to receive(:resources).and_return(nil)
      allow(rule).to receive_message_chain('actions.inspect')
      allow(rule).to receive_message_chain('roles.inspect')
      allow(rule).to receive_message_chain('condition.inspect')
      allow(rule).to receive_message_chain('resources').and_return(nil)

      # does nothing
      expect {
        result = @dummy_class._build_policy_statement(
          rule: rule,
          skip_non_existant: true
        )
      }.to_not raise_error

      # raises exception
      expect {
        result = @dummy_class._build_policy_statement(
          rule: rule,
          skip_non_existant: false
        )
      }.to raise_error(/Policy statement resource could not be resolved/)
    end

    it 'handles rules correctly' do
      rule = double(Object)

      allow(rule).to receive(:resources).and_return([])

      allow(rule).to receive_message_chain('condition').and_return('1')
      allow(rule).to receive_message_chain('actions.inspect')
      allow(rule).to receive_message_chain('roles.inspect')
      allow(rule).to receive_message_chain('resources').and_return([1])

      allow(JsonTools).to receive(:contain_value?) .and_return(true)

      # does nothing
      expect {
        result = @dummy_class._build_policy_statement(
          rule: rule,
          skip_non_existant: true
        )
      }.to_not raise_error

      # raises exception
      expect {
        result = @dummy_class._build_policy_statement(
          rule: rule,
          skip_non_existant: false
        )
      }.to raise_error(/One or more policy conditions could not be resolved/)
    end

    it 'handles policy statements correctly' do
      rule = double(Object)

      allow(rule).to receive(:resources).and_return([])

      allow(rule).to receive_message_chain('condition').and_return(nil)
      allow(rule).to receive_message_chain('actions.inspect')
      allow(rule).to receive_message_chain('roles').and_return([])

      allow(JsonTools).to receive(:contain_value?) .and_return(true)

      # does nothing
      allow(rule).to receive_message_chain('resources').and_return([nil])
      expect {
        result = @dummy_class._build_policy_statement(
          rule: rule,
          skip_non_existant: true
        )
      }.to_not raise_error

      # raises exception
      allow(rule).to receive_message_chain('resources').and_return([[], nil])
      expect {
        result = @dummy_class._build_policy_statement(
          rule: rule,
          skip_non_existant: false
        )
      }.to raise_error(/Policy statement resource could not be resolved/)
    end
  end
end
