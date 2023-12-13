require "#{BASE_DIR}/lib/util/stat_helper.rb"

RSpec.describe StatHelper do
  context '_safe_hash_merge' do
    it 'merges hashes' do
      h1 = { 'name' => 'John', 'surname' => 'Gold' }
      h2 = { 'age' => 28, 'id' => 1 }

      StatHelper._safe_hash_merge(h1, h2)

      expect(h1).to be_a_kind_of(Hash)

      expect(h1['name']).to eq('John')
      expect(h1['surname']).to eq('Gold')
      expect(h1['age']).to eq(28)
      expect(h1['id']).to eq(1)
    end

    it 'merges same key recursively' do
      h1 = { 'name' => 'John', 'surname' => 'Gold', 'props' => { 'a' => 1, 'b' => 2 } }
      h2 = { 'age' => 28, 'id' => 1, 'props' => { 'x' => 100, 'y' => 200 } }

      StatHelper._safe_hash_merge(h1, h2)

      expect(h1).to be_a_kind_of(Hash)

      expect(h1['name']).to eq('John')
      expect(h1['surname']).to eq('Gold')
      expect(h1['age']).to eq(28)
      expect(h1['id']).to eq(1)

      expect(h1['props']['a']).to eq(1)
      expect(h1['props']['b']).to eq(2)
      expect(h1['props']['x']).to eq(100)
      expect(h1['props']['y']).to eq(200)
    end

    it 'validates input' do
      expect {
        StatHelper._safe_hash_merge('', {})
      }.to raise_exception /h1 has to be of Hash type/

      expect {
        StatHelper._safe_hash_merge({}, '')
      }.to raise_exception /h2 has to be of Hash type/

      expect {
        StatHelper._safe_hash_merge(nil, {})
      }.to raise_exception /h1 has to be non-nil/

      expect {
        StatHelper._safe_hash_merge({}, nil)
      }.to raise_exception /h2 has to be non-nil/
    end
  end

  context '.start_pipeline_stage' do
    it 'validates input' do
      context = ContextClass.new(
        bucket: '1',
        storage_type: 'dummy',
        plan_key: 'AMS03-P106S01CI-BUILDARTEFACTS',
        branch_name: '3',
        build_number: '4',
        environment: '5'
      )

      expect {
        StatHelper.start_pipeline_stage(context: "1", stage_name: "2")
      }.to raise_exception(/context has to be a ContextClass instance/)

      expect {
        StatHelper.start_pipeline_stage(context: context, stage_name: 2)
      }.to raise_exception(/stage_name has to be a String/)

      expect {
        StatHelper.start_pipeline_stage(context: context, stage_name: "2")
      }.not_to raise_exception()
    end
  end

  context '.finish_pipeline_stage' do
    it 'validates its input' do
      context = ContextClass.new(
        bucket: '1',
        storage_type: 'dummy',
        plan_key: 'AMS03-P106S01CI-BUILDARTEFACTS',
        branch_name: '3',
        build_number: '4',
        environment: '5'
      )

      StatHelper.finish_pipeline_stage(context: "1", stage_name: "2")
      expect(StatHelper.get_last_finish_pipeline_stage_exception.message).to eq("context has to be a ContextClass instance")

      StatHelper.finish_pipeline_stage(context: context, stage_name: 2)
      expect(StatHelper.get_last_finish_pipeline_stage_exception.message).to eq("stage_name has to be a String")

      expect {
        StatHelper.finish_pipeline_stage(context: context, stage_name: "2")
      }.not_to raise_exception()
    end
  end

  context '.exceptions_stats' do
    it 'returns empty hash on nil' do
      expect(StatHelper.exceptions_stats(nil)).to eq({})
    end

    it 'raises exception on exception values' do
      expect {
        StatHelper.exceptions_stats(1)
      }.to raise_exception(/exception has to be an Exception instance/)

      expect {
        StatHelper.exceptions_stats("2")
      }.to raise_exception(/exception has to be an Exception instance/)

      expect {
        StatHelper.exceptions_stats([1, 2])
      }.to raise_exception(/exception has to be an Exception instance/)
    end

    it 'works on exception values' do
      expect {
        StatHelper.exceptions_stats(Exception.new("1"))
      }.not_to raise_error

      expect {
        StatHelper.exceptions_stats(ArgumentError.new("1"))
      }.not_to raise_error
    end

    it 'returns hash on exception values' do
      ex1 = Exception.new("1")
      ex2 = ArgumentError.new("2")

      result1 = StatHelper.exceptions_stats(ex1)
      result2 = StatHelper.exceptions_stats(ex2)

      expect(result1).to be_a_kind_of(Hash)
      expect(result2).to be_a_kind_of(Hash)

      expect(result1[:error][:message]).to eq(ex1.to_s)
      expect(result1[:error][:exception_type]).to eq(ex1.class.to_s)
      expect(result1[:error][:exception_backtrace]).to eq(ex1.backtrace)

      expect(result2[:error][:message]).to eq(ex2.to_s)
      expect(result2[:error][:exception_type]).to eq(ex2.class.to_s)
      expect(result2[:error][:exception_backtrace]).to eq(ex2.backtrace)
    end
  end

  context 'StatHelper' do
    it 'get_stat_fail' do
      expect { StatHelper.stats(context: nil) }
        .to raise_error(/context has to be a ContextClass instance/)

      expect { StatHelper.stats(stage_name: 'test') }
        .to raise_error(/missing keyword: :context/)
    end

    it 'get_stat_success' do
      context = ContextClass.new(
        bucket: '1',
        storage_type: 'dummy',
        plan_key: 'AMS03-P106S01CI-BUILDARTEFACTS',
        branch_name: '3',
        build_number: '4',
        environment: '5'
      )

      result = StatHelper.stats(context: context)
      expect(result.class).to eq Hash
    end

    it 'get_stat_variables' do
      context = ContextClass.new(
        bucket: '1',
        storage_type: 'dummy',
        plan_key: 'AMS03-P106S01CI-BUILDARTEFACTS',
        branch_name: '3',
        build_number: '4',
        environment: '5'
      )

      context.environment.set_variables(ENV)

      # these two variables should be set manually via additional_hash param
      # can' t automatically extract from context / env objects
      # noinspection RubyStringKeysInHashInspection
      additional_hash = {
        general: {
          run_time_in_seconds: Random.rand(1000).to_s,
          rake_task_name: Random.rand(1000).to_s,
          rake_task_phase: Random.rand(1000).to_s,
          list: [
            { some_password: 'blah' }
          ]
        }
      }
      result = StatHelper.stats(
        context: context,
        additional_hash: additional_hash
      )

      expected_top_level_keys = [
        :deployment,
        :environment,
        :pipeline,
        :general
      ]

      expect(result.class).to eq Hash

      # checking top level and inner hash variables
      # they must be present in the result hash from StatHelper.get_stat() call
      expected_top_level_keys.each { |key| expect(result.key?(key)) }
      expected_top_level_keys.each { |key| expect(result[key].is_a?(Hash)) }
      expected_top_level_keys.each { |key| expect(result[key].keys.size > 0) }
    end

    it 'get_stats_replaces_password_secrets' do
      context = ContextClass.new(
        bucket: '1',
        storage_type: 'dummy',
        plan_key: 'AMS03-P106S01CI-BUILDARTEFACTS',
        branch_name: '3',
        build_number: '4',
        environment: '5'
      )

      context.environment.set_variables(ENV)

      pass_hash = {
        :password => '123',
        :Password => '123',
        :PaSSworD => '123',

        :test_password => '123',
        :password_test => '123',
        :test_password_test => '123',

        :Test_Password => '123',
        :Password_Test => '123',
        :Test_Password_Test => '123',
      }

      additional_hash = {}

      additional_hash.merge!(pass_hash)
      additional_hash['nested_hash'] = pass_hash

      result = StatHelper.stats(
        context: context,
        additional_hash: additional_hash
      )

      expect(result.class).to eq Hash
      _validate_secret_result result, pass_hash
    end

    it 'can_track_single_timer' do
      StatHelper.start_timer('default')
      sleep 0.05
      timer_value = StatHelper.end_timer_in_seconds('default')
      expect(timer_value >= 0.05).to eq true
    end

    it 'fail_non_existing_timer' do
      expect { StatHelper.end_timer_in_seconds('non_existing_timer') }
        .to raise_error(/Cannot find timer/)
    end

    it 'can_track_multiple_timers' do
      StatHelper.start_timer('sec_3')
      sleep 0.05

      StatHelper.start_timer('sec_2')
      sleep 0.05

      StatHelper.start_timer('sec_1')
      sleep 0.05

      sec_1_value = StatHelper.end_timer_in_seconds('sec_1')
      sec_2_value = StatHelper.end_timer_in_seconds('sec_2')
      sec_3_value = StatHelper.end_timer_in_seconds('sec_3')

      _log "   - sec_1 elapsed: [#{sec_1_value}] seconds"
      _log "   - sec_2 elapsed: [#{sec_2_value}] seconds"
      _log "   - sec_3 elapsed: [#{sec_3_value}] seconds"

      expect(sec_3_value >= 0.15).to eq true
      expect(sec_2_value >= 0.10).to eq true
      expect(sec_1_value >= 0.05).to eq true
    end
  end

  private

  # @param [Hash] result_hash
  # @param [Hash] pass_hash
  def _validate_secret_result(result_hash, pass_hash)
    result_hash.each do |key, value|
      if value.is_a?(Hash)
        _validate_secret_result value, pass_hash
      else
        if pass_hash.has_key? key
          expect(value == StatHelper.secret_string).to eq true
        end
      end
    end
  end

  def _log(message)
    return unless message != nil

    if defined?(Log)
      Log.info(message)
    else
      puts message
    end
  end
end
