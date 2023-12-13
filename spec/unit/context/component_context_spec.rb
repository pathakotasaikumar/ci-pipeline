$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib/context/"))
$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib/context/storage"))
require 'component_context.rb'
require 's3_state_storage.rb'
RSpec.describe ComponentContext do
  before(:context) do
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))['unit']
    @variables = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))['variables']
    @variables.each do |component_name, variables|
      variables.each do |k, v|
        Context.component.set_variables(component_name, k => v)
      end
    end
  end

  context '.recursive_merge' do
    it 'merges recursive' do
      h1 = {
        'a1' => 11,
        'b1' => 12,
        'c1' => {
          'a1' => 11,
          'b1' => 12
        },
        {
          'a1' => 11,
          'b1' => 12
        } => 'reverse-c1'

      }

      h2 = {
        'a2' => 21,
        'b2' => 22,
        'c1' => {
          'a2' => 21,
          'b2' => 22
        },
        {
          'a2' => 21,
          'b2' => 22
        } => 'reverse-c2'
      }

      sections = {
        ams: 'ams01',
        qda: 'c031',
        as: '01',
        branch: 'master',
        ase: 'dev',
        build: '05'
      }

      dummy_storage = double(Object)
      component_context = ComponentContext.new(dummy_storage, sections)

      component_context.recursive_merge(h1, h2)
    end
  end

  context '.flush' do
    it 'flushes unmodified context' do
      sections = {
        ams: 'ams01',
        qda: 'c031',
        as: '01',
        branch: 'master',
        ase: 'dev',
        build: '05'
      }

      dummy_storage = double(Object)
      allow(dummy_storage).to receive(:load) .and_return({
        "test-component.SecurityStackId" => 52,
        "other-component" => 22
      })

      component_context = ComponentContext.new(dummy_storage, sections)

      result = component_context.flush
    end

    it 'flushes modified context' do
      sections = {
        ams: 'ams01',
        qda: 'c031',
        as: '01',
        branch: 'master',
        ase: 'dev',
        build: '05'
      }

      dummy_storage = double(Object)

      allow(dummy_storage).to receive(:save)
      allow(dummy_storage).to receive(:load) .and_return({
        "test-component.SecurityStackId" => 52,
        "other-component" => 22
      })

      component_context = ComponentContext.new(dummy_storage, sections)

      component_context.set_all({ 'a' => 1 })
      result = component_context.flush
    end
  end

  context '.variables' do
    it 'returns variables' do
      sections = {
        ams: 'ams01',
        qda: 'c031',
        as: '01',
        branch: 'master',
        ase: 'dev',
        build: '05'
      }

      dummy_storage = double(Object)
      allow(dummy_storage).to receive(:load) .and_return({
        "test-component.SecurityStackId" => 52,
        "other-component" => 22
      })

      component_context = ComponentContext.new(dummy_storage, sections)

      result = component_context.variables

      expect(result.keys.length).to eq(2)
    end

    it 'returns variables for component' do
      sections = {
        ams: 'ams01',
        qda: 'c031',
        as: '01',
        branch: 'master',
        ase: 'dev',
        build: '05'
      }

      dummy_storage = double(Object)
      allow(dummy_storage).to receive(:load) .and_return({
        "test-component.SecurityStackId" => 52,
        "other-component" => 22
      })

      component_context = ComponentContext.new(dummy_storage, sections)

      result = component_context.variables(
        component_name: "test-component"
      )

      expect(result.keys.length).to eq(1)
    end
  end

  context '.security_stack_id' do
    it 'returns security_stack_id' do
      sections = {
        ams: 'ams01',
        qda: 'c031',
        as: '01',
        branch: 'master',
        ase: 'dev',
        build: '05'
      }

      dummy_storage = double(Object)
      allow(dummy_storage).to receive(:load) .and_return({
        "test-component.SecurityStackId" => 52
      })

      component_context = ComponentContext.new(dummy_storage, sections)

      result = component_context.security_stack_id('test-component')

      expect(result).to eq(52)
    end
  end

  context '.build_number' do
    it 'returns BuildNumber' do
      sections = {
        ams: 'ams01',
        qda: 'c031',
        as: '01',
        branch: 'master',
        ase: 'dev',
        build: '05'
      }

      dummy_storage = double(Object)
      allow(dummy_storage).to receive(:load) .and_return({
        "test-component.BuildNumber" => 42
      })

      component_context = ComponentContext.new(dummy_storage, sections)

      result = component_context.build_number('test-component')

      expect(result).to eq(42)
    end
  end

  context '.stack_name' do
    it 'returns stack_name' do
      sections = {
        ams: 'ams01',
        qda: 'c031',
        as: '01',
        branch: 'master',
        ase: 'dev',
        build: '05'
      }

      dummy_storage = double(Object)
      allow(dummy_storage).to receive(:load) .and_return({
        "test-component.StackName" => "stack-42"
      })

      component_context = ComponentContext.new(dummy_storage, sections)

      result = component_context.stack_name('test-component')

      expect(result).to eq("stack-42")
    end
  end

  context '.variable' do
    it 'raises exception' do
      sections = {
        ams: 'ams01',
        qda: 'c031',
        as: '01',
        branch: 'master',
        ase: 'dev',
        build: '05'
      }

      dummy_storage = double(Object)
      allow(dummy_storage).to receive(:load) .and_return({})

      component_context = ComponentContext.new(dummy_storage, sections)

      expect {
        component_context.variable('test-component', 'non-existing-var')
      }.to raise_exception(/Could not find variable/)
    end
  end

  context '.delete_variables' do
    it 'deletes vars with prefix' do
      sections = {
        ams: 'ams01',
        qda: 'c031',
        as: '01',
        branch: 'master',
        ase: 'dev',
        build: '05'
      }

      dummy_storage = double(Object)
      allow(dummy_storage).to receive(:load) .and_return({ "test-component.x1" => 1,
                                                           "test-component.x2" => 2,
                                                           "test-component.x3" => 3,
                                                           "test-component.a1" => 4,
                                                           "test-component.b2" => 5,
                                                           "test-component.c3" => 6, })

      component_context = ComponentContext.new(dummy_storage, sections)

      component_context.delete_variables('test-component', 'test-component.x')

      # removed
      expect {
        component_context.variable('test-component', 'x1')
      }.to raise_exception(/Could not find variable/)
      expect {
        component_context.variable('test-component', 'x2')
      }.to raise_exception(/Could not find variable/)
      expect {
        component_context.variable('test-component', 'x3')
      }.to raise_exception(/Could not find variable/)

      # still there
      expect(component_context.variable('test-component', 'a1')).to eq (4)
      expect(component_context.variable('test-component', 'b2')).to eq (5)
      expect(component_context.variable('test-component', 'c3')).to eq (6)
    end
  end

  context '.default_section_variable' do
    it 'returns default values' do
      sections = {
        ams: 'ams01',
        qda: 'c031',
        as: '01',
        branch: 'master',
        ase: 'dev',
        build: '05'
      }

      dummy_storage = double(Object)
      component_context = ComponentContext.new(dummy_storage, sections)

      result = component_context.send(:default_section_variable)

      expect(result).to be_kind_of(Hash)
      expect(result).to be_truthy
    end
  end

  context 'replace_values' do
    it 'successful replacement of values 1' do
      expect(Log).to receive(:debug).with(/Replaced:/)
      expect(Context.component.replace_variables @test_data['Input1']).to eq(@test_data['Output1'])
    end

    it 'successful replacement of values 1' do
      expect(Log).to receive(:debug).with(/Replaced:/)
      expect(Context.component.replace_variables @test_data['Input2']).to eq(@test_data['Output2'])
    end

    it 'successful replacement of values 2' do
      expect(Log).to receive(:debug).with(/Replaced:/)
      expect(Log).to receive(:debug).with(/Replaced:/)
      expect(Context.component.replace_variables @test_data['Input3']).to eq(@test_data['Output3'])
    end

    it 'failed replacement of values' do
      @input = { 'ImageId' => '@unknown.ImageId' }
      expect(Log).to receive(:warn).with(/Unable to locate context variable for/)
      expect(Context.component.replace_variables @input).to eq(@input)
    end
  end

  context 'deep_find_variable' do
    it 'successful find the variable' do
      expect(Context.component.deep_find_variable(content: @test_data['Input4'], pattern: '@wildcard-qcpaws')).to eq(true)
    end

    it 'return false if not able to find the variable' do
      expect(Context.component.deep_find_variable(content: @test_data['Input1'], pattern: '@wildcard-qcpaws')).to eq(false)
    end
  end

  context 'dump_variables' do
    it 'successfully dumps variables' do
      dummy_storage = double(Object)
      sections = { ams: 'ams01', qda: 'c031', as: '01', branch: 'master', ase: 'dev', build: '05' }
      @test_data = YAML.load_file("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml")
      sample_variables = @test_data['sample_variables']
      dump_variables = @test_data['dump_variables']
      allow(AwsHelper).to receive(:kms_encrypt_data).and_return('ENCRYPTED_VALUE')
      component_context = ComponentContext.new(dummy_storage, sections)
      allow(dummy_storage).to receive(:load)
      allow(component_context).to receive(:variables).and_return(sample_variables)
      expect(component_context.dump_variables('dummy')).to eq(dump_variables)
    end

    it 'successfully dumps variables with context_skip_to_encryption_regex' do
      dummy_storage = double(Object)
      sections = { ams: 'ams01', qda: 'c031', as: '01', branch: 'master', ase: 'dev', build: '05' }
      @test_data = YAML.load_file("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml")
      sample_variables = @test_data['sample_variables_with_skip_regex']
      dump_variables = @test_data['dump_variables_with_skip_regex']
      allow(AwsHelper).to receive(:kms_encrypt_data).and_return('ENCRYPTED_VALUE')
      component_context = ComponentContext.new(dummy_storage, sections)
      allow(dummy_storage).to receive(:load)
      allow(component_context).to receive(:variables).and_return(sample_variables)
      expect(component_context.dump_variables('dummy', [], '^app.([0-9a-zA-Z_\/]+)$')).to eq(dump_variables)
    end
  end

  context '_context' do
    it 'successfully returns context' do
      dummy_storage = double(Object)
      sections = { ams: 'ams01', qda: 'c031', as: '01', branch: 'master', ase: 'dev', build: '05' }
      context_variable = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))['context_variable']
      component_context = ComponentContext.new(dummy_storage, sections)
      allow(dummy_storage).to receive(:load).and_return(context_variable)
      expect(component_context.send(:_context)).to eq(context_variable)
    end

    it 'successfully returns context for STG' do
      dummy_storage = double(Object)
      sections = { ams: 'ams01', qda: 'c031', as: '01', branch: 'master', ase: 'dev', build: '05' }
      stg_context_variable = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))['stg_context_variable']
      component_context = ComponentContext.new(dummy_storage, sections)
      allow(dummy_storage).to receive(:load).and_return(stg_context_variable)
      expect(component_context.send(:_context, ase: "stg")).to eq(stg_context_variable)
    end

    it 'successfully returns empty context' do
      dummy_storage = double(Object)
      sections = { ams: 'ams01', qda: 'c031', as: '01', branch: 'master', ase: 'dev', build: '05' }
      component_context = ComponentContext.new(dummy_storage, sections)
      allow(dummy_storage).to receive(:load).and_return({})
      expect(component_context.send(:_context, ase: "stg")).to eq({})
    end
  end

  context 'variables' do
    it 'test the variables' do
      dummy_storage = double(Object)
      sections = { ams: 'ams01', qda: 'c031', as: '01', branch: 'master', ase: 'dev', build: '05' }
      context_variable = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))['context_variable']
      component_context = ComponentContext.new(dummy_storage, sections)
      allow(component_context).to receive(:_context).and_return(context_variable)
      expect(component_context.variables["dynamo.MyTableName"]).to eq('dummy-dynamodb-table1')
    end

    it 'test the variables' do
      dummy_storage = double(Object)
      sections = { ams: 'ams01', qda: 'c031', as: '01', branch: 'master', ase: 'dev', build: '05' }
      stg_context_variable = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))['stg_context_variable']
      component_context = ComponentContext.new(dummy_storage, sections)
      component_section = { ase: "stg" }
      allow(component_context).to receive(:_context).and_return(stg_context_variable)
      expect(component_context.variables(**component_section)).to eq(stg_context_variable)
    end
  end

  context '_load_application_secret_parameters' do
    it 'successfully loads parameters from ssm service' do
      allow(Context).to receive_message_chain('environment.variable')
        .with('local_pipeline_unit_testing')
        .and_return(false)

      param1 = double(Object)
      allow(param1).to receive(:name).and_return('/Application/param1')
      allow(param1).to receive(:value).and_return('dummy-value-1')

      param2 = double(Object)
      allow(param2).to receive(:name).and_return('/Application/param2')
      allow(param2).to receive(:value).and_return('dummy-value-2')

      param3 = double(Object)
      allow(param3).to receive(:name).and_return('/Application/param2/_common')
      allow(param3).to receive(:value).and_return('dummy-value-3')

      allow(AwsHelper).to receive(:ssm_get_parameters_by_path).and_return([param1, param2, param3])

      dummy_storage = double(Object)
      sections = { ams: 'ams01', qda: 'c031', as: '01', branch: 'master', ase: 'dev', build: '05' }
      component_context = ComponentContext.new(dummy_storage, sections)
      component_context._load_application_secret_parameters
    end

    it 'fails to load parameters from ssm service' do
      allow(Context).to receive_message_chain('environment.variable')
        .with('local_pipeline_unit_testing')
        .and_return(false)

      allow(AwsHelper).to receive(:ssm_get_parameters_by_path).and_raise(RuntimeError)

      dummy_storage = double(Object)
      sections = { ams: 'ams01', qda: 'c031', as: '01', branch: 'master', ase: 'dev', build: '05' }
      component_context = ComponentContext.new(dummy_storage, sections)
      expect(Log).to receive(:error).with(/Unable to fetch Application secret parameters/)
      component_context._load_application_secret_parameters
    end
  end
end # RSpec.describe
