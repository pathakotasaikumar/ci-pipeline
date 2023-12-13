$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib/context"))
require 'context/environment_context.rb'

RSpec.describe ContextStorage do
  before(:context) do
    @sections = {
      ams: 'ams01',
      qda: 'c031',
      as: '01',
      branch: 'master',
      ase: 'dev',
      build: '05'
    }
  end

  context '.initialise' do
    it 'creates an instance' do
      dummy_storage = double(Object)

      context = ContextStorage.new(
        name: 'Pipeline',
        state_storage: dummy_storage,
        path: [@sections[:ams], @sections[:qda], @sections[:as], @sections[:ase], @sections[:branch], @sections[:build], "Pipeline"],
        sync: true
      )
    end

    it 'creates unsynched instance' do
      dummy_storage = double(Object)

      expect(dummy_storage).to receive(:load)

      context = ContextStorage.new(
        name: 'Pipeline',
        state_storage: dummy_storage,
        path: [@sections[:ams], @sections[:qda], @sections[:as], @sections[:ase], @sections[:branch], @sections[:build], "Pipeline"],
        sync: false
      )

      result = context.reload
      context.variables

      expect(result).to eq(context)

      expect(result.instance_variable_get(:@loaded)).to eq(true)
    end
  end

  context '.initialise' do
    it 'creates an instance' do
      dummy_storage = double(Object)

      context = ContextStorage.new(
        name: 'Pipeline',
        state_storage: dummy_storage,
        path: [@sections[:ams], @sections[:qda], @sections[:as], @sections[:ase], @sections[:branch], @sections[:build], "Pipeline"],
        sync: true
      )
    end
  end

  context '.reload' do
    it 'reloads' do
      dummy_storage = double(Object)

      context = ContextStorage.new(
        name: 'Pipeline',
        state_storage: dummy_storage,
        path: [@sections[:ams], @sections[:qda], @sections[:as], @sections[:ase], @sections[:branch], @sections[:build], "Pipeline"],
        sync: true
      )

      result = context.reload

      expect(result).to eq(context)

      expect(result.instance_variable_get(:@loaded)).to eq(false)
      expect(result.instance_variable_get(:@context)).to eq(nil)
    end

    it 'does not flush unmodified' do
      dummy_storage = double(Object)

      context = ContextStorage.new(
        name: 'Pipeline',
        state_storage: dummy_storage,
        path: [@sections[:ams], @sections[:qda], @sections[:as], @sections[:ase], @sections[:branch], @sections[:build], "Pipeline"],
        sync: true
      )

      expect(dummy_storage).to receive(:save)
        .exactly(0).times

      result = context.flush

      expect(result).to eq(context)
    end

    it 'flushes modified' do
      dummy_storage = double(Object)

      context = ContextStorage.new(
        name: 'Pipeline',
        state_storage: dummy_storage,
        path: [@sections[:ams], @sections[:qda], @sections[:as], @sections[:ase], @sections[:branch], @sections[:build], "Pipeline"],
        sync: true
      )

      expect(dummy_storage).to receive(:load)
      expect(dummy_storage).to receive(:save)
        .exactly(1).times

      context.set_variables({ 'a' => 1 })
      result = context.flush

      expect(result).to eq(context)
    end
  end

  context '.hash methods' do
    it 'finds keys' do
      dummy_storage = double(Object)

      context = ContextStorage.new(
        name: 'Pipeline',
        state_storage: dummy_storage,
        path: [@sections[:ams], @sections[:qda], @sections[:as], @sections[:ase], @sections[:branch], @sections[:build], "Pipeline"],
        sync: true
      )

      allow(dummy_storage).to receive(:load) .and_return({
        'name' => 'Smith'
      })

      expect(context.has_key?('non-existing-key')).to eq(false)
      expect(context.has_key?('name')).to eq(true)
    end

    it 'finds keys' do
      dummy_storage = double(Object)

      context = ContextStorage.new(
        name: 'Pipeline',
        state_storage: dummy_storage,
        path: [@sections[:ams], @sections[:qda], @sections[:as], @sections[:ase], @sections[:branch], @sections[:build], "Pipeline"],
        sync: true
      )

      allow(dummy_storage).to receive(:load) .and_return({
        'name' => 'Smith'
      })

      expect(context.has_key?('non-existing-key')).to eq(false)
      expect(context.has_key?('name')).to eq(true)

      expect(context['name']).to eq('Smith')

      context["surname"] = 'Wick'
      expect(context["surname"]).to eq("Wick")
    end

    it 'finds variables' do
      dummy_storage = double(Object)

      context = ContextStorage.new(
        name: 'Pipeline',
        state_storage: dummy_storage,
        path: [@sections[:ams], @sections[:qda], @sections[:as], @sections[:ase], @sections[:branch], @sections[:build], "Pipeline"],
        sync: true
      )

      allow(dummy_storage).to receive(:load) .and_return({
        'name' => 'Smith'
      })

      expect(context.variable('name')).to eq('Smith')
      expect(context.variable('surname', 'Agent')).to eq('Agent')

      expect {
        context.variable('surname')
      }.to raise_exception(/Could not find variable/)
    end

    it 'sets variables' do
      dummy_storage = double(Object)

      context = ContextStorage.new(
        name: 'Pipeline',
        state_storage: dummy_storage,
        path: [@sections[:ams], @sections[:qda], @sections[:as], @sections[:ase], @sections[:branch], @sections[:build], "Pipeline"],
        sync: true
      )

      allow(dummy_storage).to receive(:load) .and_return({
        'name' => 'Smith'
      })

      expect(context.variable('name')).to eq('Smith')
      expect(context.variable('surname', 'Agent')).to eq('Agent')

      context.set_variables({
        'surname' => 'Agent',
        'name' => 'John'
      })

      expect(context.variable('name')).to eq('John')
      expect(context.variable('surname')).to eq('Agent')
    end
  end
end
