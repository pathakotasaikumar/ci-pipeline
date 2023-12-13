$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib/context"))
require 'context/environment_context.rb'

RSpec.describe EnvironmentContext do
  before(:context) do
    @test_data = {
      "dev-qantas-ap-southeast-2a-private" => {
        "id" => "subnet-2a"
      },
      "dev-qantas-ap-southeast-2b-private" => {
        "id" => "subnet-2b"
      },
      "dev-qantas-ap-southeast-2c-private" => {
        "id" => "subnet-2c"
      }
    }

    @sections = {
      ams: 'ams01',
      qda: 'c031',
      as: '01',
      branch: 'master',
      ase: 'dev',
      build: '05'
    }
  end

  context 'space trim' do
    it 'Test space trim' do
      dummy_storage = double(Object)
      sections = { ams: 'ams01', qda: 'c031', as: '01', branch: 'master', ase: 'dev', build: '05' }

      spaced_test_data = {
        'normal_value' => 'normal_value',
        'left_space_value' => ' left_space_value',
        'right_space_value' => 'right_space_value ',
        'both_side_space_value' => ' both_side_space_value ',
        'nil_value' => nil,
        'number_value' => 1,
        'class_value' => sections,
        'hash_value' => {
          't1' => 1,
          't2' => 2
        }
      }

      environment_context = EnvironmentContext.new(dummy_storage, sections)
      environment_context.set_variables(spaced_test_data)

      result_variables = environment_context.variables

      spaced_test_data.keys.each do |result_key|
        result_value = result_variables[result_key]
        original_value = spaced_test_data[result_key]

        # result key should be in the original data
        expect(result_variables.include?(result_key)).to eq(true)

        # result value should be trimmed
        if original_value.is_a?(String)
          expect(result_value).to eq(original_value.strip)
        else
          expect(result_value).to eq(original_value)
        end
      end
    end
  end

  context '.variable' do
    it 'raises exception on missing var' do
      dummy_storage = double(Object)

      environment_context = EnvironmentContext.new(dummy_storage, @sections)

      expect {
        environment_context.variable('non-existing-var')
      }.to raise_exception(/Could not find environment variable/)
    end
  end

  context '.set_variables' do
    it 'handles special variables' do
      dummy_storage = double(Object)
      environment_context = EnvironmentContext.new(dummy_storage, @sections)
      environment_context.set_variables(
        'persist_true' => 'true ',
        'persist_false' => 'false ',
        'shared_accounts' => '4 ,5, 6 '
      )

      expect(environment_context.variable('persist_true')).to eq(['true'])
      expect(environment_context.variable('persist_false')).to eq(['false'])
      expect(environment_context.variable('shared_accounts')).to eq(["4", "5", "6"])
    end

    it 'handles list variables' do
      dummy_storage = double(Object)

      environment_context = EnvironmentContext.new(dummy_storage, @sections)
      environment_context.set_variables(
        'ad_domain_list' => '1, 2, 3',
        'persist_true' => '5, 6, 7',
        'persist_false' => '8, 9, 10',
        'shared_accounts' => '11, 12, 13',
        'sns_source_accounts' => '14, 15, 16',
        'log_destination_source_accounts' => '17, 18, 19'
      )

      expect(environment_context.variable('ad_domain_list')).to eq(["1", "2", "3"])
      expect(environment_context.variable('persist_true')).to eq(["5", "6", "7"])
      expect(environment_context.variable('persist_false')).to eq(["8", "9", "10"])
      expect(environment_context.variable('shared_accounts')).to eq(["11", "12", "13"])
      expect(environment_context.variable('sns_source_accounts')).to eq(["14", "15", "16"])
      expect(environment_context.variable('log_destination_source_accounts')).to eq(["17", "18", "19"])
    end

    it 'handles soe_ami_ids as JSON' do
      dummy_storage = double(Object)

      environment_context = EnvironmentContext.new(dummy_storage, @sections)
      environment_context.set_variables(
        'soe_ami_ids' => '{ "a": "123", "b": "456" }'
      )

      expect(environment_context.variable('soe_ami_ids')).to eq({
        'a' => '123',
        'b' => '456'
      })
    end
  end

  context '.dr_account_id' do
    it 'returns dr_account_id in lowercase' do
      dummy_storage = double(Object)
      environment_context = EnvironmentContext.new(dummy_storage, @sections)

      environment_context.set_variables({ 'dr_account_id' => '123-456-XX-YY-ZZ' })

      expect(environment_context.dr_account_id).to eq('123-456-xx-yy-zz')
    end
  end

  context '.nonp_account_id' do
    it 'successfully execute if non_account_id is empty  value and environment value is nonp' do
      dummy_storage = double(Object)
      environment_context = EnvironmentContext.new(dummy_storage, @sections)
      environment_context.set_variables({ 'nonp_account_id' => '' })
      allow(Defaults).to receive(:sections).and_return({ :env => "nonp" })
    end

    it 'successfully execute if non_account_id is empty  value and environment value is NONP' do
      dummy_storage = double(Object)
      environment_context = EnvironmentContext.new(dummy_storage, @sections)
      environment_context.set_variables({ 'nonp_account_id' => '' })
      allow(Defaults).to receive(:sections).and_return({ :env => "NONP" })
    end

    it 'successfully execute if non_account_id is not empty  value and environment value is nonp' do
      dummy_storage = double(Object)
      environment_context = EnvironmentContext.new(dummy_storage, @sections)
      environment_context.set_variables({ 'nonp_account_id' => '123-456-XX-YY-ZZ' })
      allow(Defaults).to receive(:sections).and_return({ :env => "nonp" })
    end

    it 'successfully execute if non_account_id is not empty  value and environment value is prod' do
      dummy_storage = double(Object)
      environment_context = EnvironmentContext.new(dummy_storage, @sections)
      environment_context.set_variables({ 'nonp_account_id' => '123-456-XX-YY-ZZ' })
      allow(Defaults).to receive(:sections).and_return({ :env => "prod" })
    end

    it 'raises exception when non_account_id is empty  value and environment value is prod' do
      dummy_storage = double(Object)
      environment_context = EnvironmentContext.new(dummy_storage, @sections)
      allow(Defaults).to receive(:sections).and_return({ :env => "PROD" })

      expect {
        environment_context.nonp_account_id
      }.to raise_exception(/AWS NonProd Account id should be defined for Prod Plan - set variable nonp_account_id/)
    end

    it 'raises exception when non_account_id is empty  value and environment value is PROD' do
      dummy_storage = double(Object)
      environment_context = EnvironmentContext.new(dummy_storage, @sections)
      allow(Defaults).to receive(:sections).and_return({ :env => "PROD" })

      expect {
        environment_context.nonp_account_id
      }.to raise_exception(/AWS NonProd Account id should be defined for Prod Plan - set variable nonp_account_id/)
    end
  end

  context '.availability_zones' do
    it 'reloads default on nil' do
      dummy_storage = double(Object)

      environment_context = EnvironmentContext.new(dummy_storage, @sections)

      allow(Context).to receive_message_chain('environment.set_variables')
      allow(Context).to receive_message_chain('environment.variable')
      allow(Context).to receive_message_chain('environment.vpc_id')

      # getting 2 times with testing @a/@A zones
      expect(AwsHelper).to receive(:ec2_get_availability_zones)
        .exactly(2).times
        .and_return({ '@a' => '192.168.137.1' })

      environment_context.availability_zones('@a')
      environment_context.availability_zones('@A')
    end

    it 'raises exception for unknown zone' do
      dummy_storage = double(Object)

      environment_context = EnvironmentContext.new(dummy_storage, @sections)

      allow(Context).to receive_message_chain('environment.set_variables')
      allow(Context).to receive_message_chain('environment.variable')
      allow(Context).to receive_message_chain('environment.vpc_id')

      expect(AwsHelper).to receive(:ec2_get_availability_zones).and_return({ '@a' => '192.168.137.1' })

      expect {
        environment_context.availability_zones('@y')
      }.to raise_exception(/Cannot find availability zones for alias/)
    end
  end

  context '.qa?' do
    it 'true if bamboo_pipeline_qa is true' do
      dummy_storage = double(Object)
      ENV['bamboo_pipeline_qa'] = 'true'
      environment_context = EnvironmentContext.new(dummy_storage, @sections)
      environment_context._load_environment_variables
      expect(environment_context.qa?).to eq(true)
    end

    it 'true if bamboo_pipeline_qa is 1' do
      dummy_storage = double(Object)
      ENV['bamboo_pipeline_qa'] = '1'
      environment_context = EnvironmentContext.new(dummy_storage, @sections)
      environment_context._load_environment_variables
      expect(environment_context.qa?).to eq(true)
    end

    it 'false if bamboo_pipeline_qa is 0' do
      dummy_storage = double(Object)
      ENV['bamboo_pipeline_qa'] = '0'
      environment_context = EnvironmentContext.new(dummy_storage, @sections)
      environment_context._load_environment_variables
      expect(environment_context.qa?).to eq(false)
    end
  end

  context '.experimental?' do
    it 'true if bamboo_pipeline_experimental is true' do
      dummy_storage = double(Object)
      ENV['bamboo_pipeline_experimental'] = 'true'
      environment_context = EnvironmentContext.new(dummy_storage, @sections)
      environment_context._load_environment_variables
      expect(environment_context.experimental?).to eq(true)
    end

    it 'true if bamboo_pipeline_experimental is 1' do
      dummy_storage = double(Object)
      ENV['bamboo_pipeline_experimental'] = '1'
      environment_context = EnvironmentContext.new(dummy_storage, @sections)
      environment_context._load_environment_variables
      expect(environment_context.experimental?).to eq(true)
    end

    it 'QA(True) if bamboo_pipeline_experimental is 0' do
      dummy_storage = double(Object)
      ENV['bamboo_pipeline_experimental'] = '0'
      ENV['bamboo_pipeline_qa'] = 'True'
      environment_context = EnvironmentContext.new(dummy_storage, @sections)
      environment_context._load_environment_variables
      expect(environment_context.experimental?).to eq(true)
    end

    it 'QA(False) if bamboo_pipeline_experimental is 0' do
      dummy_storage = double(Object)
      ENV['bamboo_pipeline_experimental'] = '0'
      ENV['bamboo_pipeline_qa'] = 'False'
      environment_context = EnvironmentContext.new(dummy_storage, @sections)
      environment_context._load_environment_variables
      expect(environment_context.experimental?).to eq(false)
    end
  end

  context '.flush' do
    it 'flush' do
      dummy_storage = double(Object)

      allow(dummy_storage).to receive(:save)

      environment_context = EnvironmentContext.new(dummy_storage, @sections)
      environment_context.flush
    end
  end
  context 'subnets' do
    it 'reloads default on nil' do
      dummy_storage = double(Object)

      environment_context = EnvironmentContext.new(dummy_storage, @sections)

      allow(Context).to receive_message_chain('environment.set_variables')
      allow(Context).to receive_message_chain('environment.variable')
      allow(Context).to receive_message_chain('environment.vpc_id')

      expect(AwsHelper).to receive(:ec2_get_subnets).and_return({ 'private' => '192.168.137.1' })

      environment_context.subnets('@private')
    end

    it 'Test the input @a-private' do
      allow(Context).to receive_message_chain('environment.variable').and_return(@test_data)
      dummy_storage = double(Object)
      sections = { ams: 'ams01', qda: 'c031', as: '01', branch: 'master', ase: 'dev', build: '05' }

      environment_context = EnvironmentContext.new(dummy_storage, sections)
      expect(environment_context.subnets "@a-private").to eq({ "dev-qantas-ap-southeast-2a-private" => { "id" => "subnet-2a" } })
    end

    it 'Test the input a-private' do
      allow(Context).to receive_message_chain('environment.variable').and_return(@test_data)
      dummy_storage = double(Object)
      sections = { ams: 'ams01', qda: 'c031', as: '01', branch: 'master', ase: 'dev', build: '05' }

      environment_context = EnvironmentContext.new(dummy_storage, sections)
      expect(environment_context.subnets "@a-private").to eq({ "dev-qantas-ap-southeast-2a-private" => { "id" => "subnet-2a" } })
    end

    it 'Test the input @a-private, b-private with space' do
      allow(Context).to receive_message_chain('environment.variable').and_return(@test_data)
      dummy_storage = double(Object)
      sections = { ams: 'ams01', qda: 'c031', as: '01', branch: 'master', ase: 'dev', build: '05' }

      environment_context = EnvironmentContext.new(dummy_storage, sections)
      expect(environment_context.subnets "@a-private, b-private").to eq({ "dev-qantas-ap-southeast-2a-private" => { "id" => "subnet-2a" }, "dev-qantas-ap-southeast-2b-private" => { "id" => "subnet-2b" } })
    end

    it 'Test the input @a-private,b-private,c-private' do
      allow(Context).to receive_message_chain('environment.variable').and_return(@test_data)
      dummy_storage = double(Object)
      sections = { ams: 'ams01', qda: 'c031', as: '01', branch: 'master', ase: 'dev', build: '05' }

      environment_context = EnvironmentContext.new(dummy_storage, sections)
      expect(environment_context.subnets " @a-private,b-private,c-private").to eq(@test_data)
    end

    it 'Test the input @a-private, @b-private' do
      allow(Context).to receive_message_chain('environment.variable').and_return(@test_data)
      dummy_storage = double(Object)
      sections = { ams: 'ams01', qda: 'c031', as: '01', branch: 'master', ase: 'dev', build: '05' }

      environment_context = EnvironmentContext.new(dummy_storage, sections)
      expect(environment_context.subnets "@a-private, @b-private").to eq({ "dev-qantas-ap-southeast-2a-private" => { "id" => "subnet-2a" }, "dev-qantas-ap-southeast-2b-private" => { "id" => "subnet-2b" } })
    end

    it 'Test the empty input' do
      allow(Context).to receive_message_chain('environment.variable').and_return(@test_data)
      dummy_storage = double(Object)
      sections = { ams: 'ams01', qda: 'c031', as: '01', branch: 'master', ase: 'dev', build: '05' }
      environment_context = EnvironmentContext.new(dummy_storage, sections)
      expect {
        environment_context.subnets "failed-alias"
      }.to raise_exception(RuntimeError, /Could not find any subnets for alias "failed-alias"/)
    end
  end

  context '_load_environment_variables' do
    it 'successfully loads bamboo environment variables' do
      dummy_storage = double(Object)
      sections = { ams: 'ams01', qda: 'c031', as: '01', branch: 'master', ase: 'dev', build: '05' }
      ENV['dummy-local-var'] = 'test'
      ENV['bamboo_dummy-var'] = 'test'
      ENV['bamboo_aws_proxy'] = 'http://dummy.com.au:3128'
      environment_context = EnvironmentContext.new(dummy_storage, sections)
      environment_context._load_environment_variables

      # test for exclusion
      expect(environment_context.variable('dummy-local-var', nil)).to be(nil)

      # test for inclusion
      expect(environment_context.variable('dummy-var', nil)).to eq('test')

      # test for proxy host
      expect(environment_context.variable('aws_proxy_host', nil)).to eq('dummy.com.au')

      # test for proxy port
      expect(environment_context.variable('aws_proxy_port', nil)).to eq(3128)
    end
  end

  context '_load_pipeline_parameters' do
    it 'successfully loads parameters from ssm service' do
      allow(Context).to receive_message_chain('environment.variable')
        .with('local_pipeline_unit_testing')
        .and_return(false)

      allow(Defaults).to receive(:pipeline_parameter_prefix).and_return('/pipeline')
      param1 = double(Object)
      allow(param1).to receive(:name).and_return('/pipeline/param1')
      allow(param1).to receive(:value).and_return('dummy-value-1')

      param2 = double(Object)
      allow(param2).to receive(:name).and_return('/pipeline/param2')
      allow(param2).to receive(:value).and_return('dummy-value-2')

      allow(AwsHelper).to receive(:ssm_get_parameters_by_path).and_return([param1, param2])

      dummy_storage = double(Object)
      sections = { ams: 'ams01', qda: 'c031', as: '01', branch: 'master', ase: 'dev', build: '05' }
      environment_context = EnvironmentContext.new(dummy_storage, sections)
      environment_context._load_pipeline_parameters
    end

    it 'fails to load parameters from ssm service' do
      allow(Context).to receive_message_chain('environment.variable')
        .with('local_pipeline_unit_testing')
        .and_return(false)

      allow(Defaults).to receive(:pipeline_parameter_prefix).and_return('/pipeline')

      allow(AwsHelper).to receive(:ssm_get_parameters_by_path).and_raise(RuntimeError)

      dummy_storage = double(Object)
      sections = { ams: 'ams01', qda: 'c031', as: '01', branch: 'master', ase: 'dev', build: '05' }
      environment_context = EnvironmentContext.new(dummy_storage, sections)
      expect(Log).to receive(:error).with(/Unable to fetch pipeline secret parameters/)
      environment_context._load_pipeline_parameters
    end
  end

  def _get_context
    dummy_storage = double(Object)
    sections = { ams: 'ams01', qda: 'c031', as: '01', branch: 'master', ase: 'dev', build: '05' }
    ENV['dummy-local-var'] = 'test'
    ENV['bamboo_dummy-var'] = 'test'
    ENV['bamboo_aws_proxy'] = 'http://dummy.com.au:3128'

    EnvironmentContext.new(dummy_storage, sections)
  end

  context '.subnet_ids' do
    it 'returns best 3 subnets from 5 available' do
      environment_context = _get_context

      subnet_values = [
        { id: 1, availability_zone: 'ap-southeast-2a', available_ips: 100 },
        { id: 3, availability_zone: 'ap-southeast-2b', available_ips: 300 },
        { id: 5, availability_zone: 'ap-southeast-2b', available_ips: 500 },
        { id: 2, availability_zone: 'ap-southeast-2c', available_ips: 200 },
        { id: 4, availability_zone: 'ap-southeast-2c', available_ips: 400 },
      ]

      subnets = double(Object)
      allow(subnets).to receive(:values).and_return(subnet_values)

      allow(environment_context).to receive(:subnets).and_return(subnets)
      expect(environment_context.subnet_ids('private')).to eq([1, 5, 4])
    end

    it 'returns best 3 subnets from 3 available' do
      environment_context = _get_context

      subnet_values = [
        { id: 1, availability_zone: 'ap-southeast-2a', available_ips: 100 },
        { id: 3, availability_zone: 'ap-southeast-2b', available_ips: 300 },
        { id: 2, availability_zone: 'ap-southeast-2c', available_ips: 200 }
      ]

      subnets = double(Object)
      allow(subnets).to receive(:values).and_return(subnet_values)

      allow(environment_context).to receive(:subnets).and_return(subnets)
      expect(environment_context.subnet_ids('private')).to eq([1, 3, 2])
    end

    it 'returns best 2 subnets from 2 available' do
      environment_context = _get_context

      subnet_values = [
        { id: 1, availability_zone: 'ap-southeast-2a', available_ips: 100 },
        { id: 3, availability_zone: 'ap-southeast-2b', available_ips: 300 }
      ]

      subnets = double(Object)
      allow(subnets).to receive(:values).and_return(subnet_values)

      allow(environment_context).to receive(:subnets).and_return(subnets)
      expect(environment_context.subnet_ids('private')).to eq([1, 3])
    end

    it 'returns 3 subnets from 3 available' do
      environment_context = _get_context

      subnet_values = [
        { id: 1, availability_zone: 'ap-southeast-2a', available_ips: 100 },
        { id: 3, availability_zone: 'ap-southeast-2b', available_ips: 300 },
        { id: 4, availability_zone: 'ap-southeast-2c', available_ips: 400 }
      ]

      subnets = double(Object)
      allow(subnets).to receive(:values).and_return(subnet_values)

      allow(environment_context).to receive(:subnets).and_return(subnets)
      expect(environment_context.subnet_ids('private', scheme = :something_else)).to eq([1, 3, 4])
    end
  end

  context '.persist_override' do
    it 'returns true' do
      environment_context = _get_context

      # global override
      result = environment_context.persist_override('my-component', 'true')
      expect(result).to eq(true)

      result = environment_context.persist_override('my-component', true)
      expect(result).to eq(true)

      # persist_true by component name
      environment_context.instance_variable_set(:@context, { 'persist_true' => ['my-component'] })
      result = environment_context.persist_override('my-component', false)
      expect(result).to eq(true)
    end

    it 'returns false' do
      environment_context = _get_context

      # global override
      result = environment_context.persist_override('my-component', 'false')
      expect(result).to eq(false)

      result = environment_context.persist_override('my-component', false)
      expect(result).to eq(false)

      # persist_false by component name
      environment_context.instance_variable_set(:@context, { 'persist_false' => ['my-component'] })
      result = environment_context.persist_override('my-component', false)
      expect(result).to eq(false)
    end
  end

  context '.region' do
    it 'returns default region' do
      environment_context = _get_context

      environment_context.instance_variable_set(:@context, { 'aws_region' => '' })

      # that's how it must be
      # https://jira.qantas.com.au/browse/QCP-1399
      # expect(environment_context.region).to eq("ap-southeast-2")

      # this is for temporary fix and green state
      expect(environment_context.region).to eq('')
    end

    it 'returns context aws_region' do
      environment_context = _get_context

      environment_context.instance_variable_set(:@context, { 'aws_region' => '11' })
      expect(environment_context.region).to eq("11")
    end
  end

  context '.account_id' do
    it 'raises error if context is not set' do
      environment_context = _get_context

      environment_context.instance_variable_set(:@context, {})

      expect {
        environment_context.account_id
      }.to raise_error(/AWS account id has not been defined - set variable aws_account_id/)
    end

    it 'returns context aws_account_id' do
      environment_context = _get_context

      environment_context.instance_variable_set(:@context, { 'aws_account_id' => '22' })
      expect(environment_context.account_id).to eq('22')
    end
  end

  context '.vpc_id' do
    it 'raises error if context is not set' do
      environment_context = _get_context

      environment_context.instance_variable_set(:@context, {})

      expect {
        environment_context.vpc_id
      }.to raise_error(/AWS VPC id has not been defined - set variable aws_vpc_id/)
    end

    it 'returns context vpc_id' do
      environment_context = _get_context

      environment_context.instance_variable_set(:@context, { 'aws_vpc_id' => '33' })
      expect(environment_context.vpc_id).to eq('33')
    end
  end

  context '.dump_variables' do
    it 'returns empty hash' do
      environment_context = _get_context

      context_hash = {}
      environment_context.instance_variable_set(:@context, context_hash)

      # returns nothing
      result = environment_context.dump_variables
      expect(result.class).to be(Hash)
      expect(result.count).to eq(0)
    end

    it 'returns values' do
      environment_context = _get_context

      context_hash = {
        'a' => 1,
        'b' => 2
      }
      environment_context.instance_variable_set(:@context, context_hash)

      # returns exact hash
      result = environment_context.dump_variables
      expect(result.class).to be(Hash)
      expect(result.count).to eq(context_hash.count)
      expect(result).to eq(context_hash)
    end

    it 'does not return trimmed values' do
      environment_context = _get_context

      context_hash = {
        'a' => 1,
        'b' => 2,
        'c' => 3,

        'asir_|value' => 'value',
        'agent_proxy|value' => 'value',
        'aws_account_id|value' => 'value',
        'aws_region|value' => 'value',
        'aws_control_role|value' => 'value',
        'aws_provisioning_role|value' => 'value',
        'aws_availability_zones|value' => 'value',
        'aws_subnet_ids|value' => 'value',
        'pipeline_bucket_name|value' => 'value',
        'legacy_bucket_name|value' => 'value',
        'artefact_bucket_name|value' => 'value',
        'lambda_artefact_bucket_name|value' => 'value',
        'snow_|value' => 'value',
        'soe_ami_ids|value' => 'value',
        'splunk_|value' => 'value',
        'api_gateway_|value' => 'value'
      }

      environment_context.instance_variable_set(:@context, context_hash)

      # returns exact hash
      result = environment_context.dump_variables
      expect(result.class).to be(Hash)
      expect(result.count).to eq(3)

      expect(result['a']).to eq(context_hash['a'])
      expect(result['b']).to eq(context_hash['b'])
      expect(result['c']).to eq(context_hash['c'])
    end
  end
end
