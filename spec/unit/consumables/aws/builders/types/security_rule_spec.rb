$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws/builders/types")
require "security_rule"

RSpec.describe SecurityRule do
  before(:context) do
  end

  context '.instantiate' do
    it 'can create instance' do
      SecurityRule.new
    end

    it '.= ovverride' do
      class MySecurityRule < SecurityRule
        def _state
          return '1'
        end
      end

      a = MySecurityRule.new
      b = MySecurityRule.new

      # this is bad
      # _state method should be abstract at SecurityRule class
      # it is meant to be overwrittem by inherited class IpSecurityRule
      # but having no implementation or raising exception at SecurityRule isn't good
      allow(a).to receive(:_state).and_return('1')
      allow(b).to receive(:_state).and_return('1')

      expect(a == b).to eq(true)

      allow(a).to receive(:_state).and_return('1')
      allow(b).to receive(:_state).and_return('2')

      expect(a == b).to eq(false)
    end
  end
end # RSpec.describe

RSpec.describe IpSecurityRule do
  before(:context) do
  end

  context '.instantiate' do
    it 'can create instance' do
      IpSecurityRule.new(
        sources: [],
        destination: 'destination',
        ports: [],
        name: nil,
        allow_cidr: nil,
        allow_direct_sg: true
      )
    end

    it 'raises error on non-direct_sg & allow_direct_sg = false' do
      expect {
        IpSecurityRule.new(
          sources: [],
          destination: 'sg-destination',
          ports: [],
          name: nil,
          allow_cidr: nil,
          allow_direct_sg: false
        )
      }.to raise_error(/SecurityGroup id is not allowed on destination/)
    end

    it 'does not raise error on non-direct_sg & allow_direct_sg = true' do
      IpSecurityRule.new(
        sources: [],
        destination: 'sg-destination',
        ports: [],
        name: nil,
        allow_cidr: nil,
        allow_direct_sg: true
      )
    end

    it 'does not allow CIDR on number source' do
      expect {
        IpSecurityRule.new(
          sources: ['1234567890'],
          destination: 'sg-destination',
          ports: [],
          name: nil,
          allow_cidr: false,
          allow_direct_sg: true
        )
      }.to raise_error(/CIDR format is not allowed on source/)
    end

    it 'allows CIDR on component source' do
      expect {
        IpSecurityRule.new(
          sources: ['my-component'],
          destination: 'sg-destination',
          ports: [],
          name: nil,
          allow_cidr: false,
          allow_direct_sg: true
        )
      }.not_to raise_error
    end

    it 'does not allow direct security group on sg-source' do
      expect {
        IpSecurityRule.new(
          sources: ['sg-my-group'],
          destination: 'destination',
          ports: [],
          name: nil,
          allow_cidr: true,
          allow_direct_sg: false
        )
      }.to raise_error(/Security Group id is not allowed on source/)
    end

    it 'alllows direct security group on sg-source' do
      expect {
        IpSecurityRule.new(
          sources: ['my-component'],
          destination: 'destination',
          ports: [],
          name: nil,
          allow_cidr: false,
          allow_direct_sg: true
        )
      }.not_to raise_error
    end
  end

  context '._state' do
    it 'returns value' do
      source = ['1', '2', '3']
      destination = "destination"
      ports = ['tcp:90-91']

      rule = IpSecurityRule.new(
        sources: source,
        destination: destination,
        ports: ports,
        name: nil,
        allow_cidr: nil,
        allow_direct_sg: true
      )

      result = rule._state

      expect(result.class).to be(Array)
      expect(result.count).to eq(3)

      expect(result[0]).to eq(source)
      expect(result[1]).to eq(destination)

      expect(result[2].count).to eq(1)

      result_ip = result[2][0]

      expect(result_ip).to eq(IpPort.from_specification('tcp:90-91'))
    end
  end
end

RSpec.describe IamSecurityRule do
  before(:context) do
  end

  context '.instantiate' do
    it 'can create instance' do
      IamSecurityRule.new(
      )
    end
  end

  context '._state' do
    it 'returns value' do
      roles = ['1', '2', '3']
      resources = ["5,6,7"]
      actions = ['a1', 'a2']
      conditions = ['c1', 'c2']

      rule = IamSecurityRule.new(
        roles: roles,
        resources: resources,
        actions: actions,
        condition: conditions
      )

      result = rule._state

      expect(result.class).to be(Array)
      expect(result.count).to eq(4)

      expect(result[0]).to eq(roles)
      expect(result[1]).to eq(resources)
      expect(result[2]).to eq(actions)
      expect(result[3]).to eq(conditions)
    end
  end
end
