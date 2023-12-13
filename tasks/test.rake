require 'rake'

namespace :test do

  desc "Perform all unit tests"
  task :unit do
    Log.info "Running all unit tests"
   run_tests('test:unit', "unit")
  end

  desc "Perform all acceptance tests"
  task :acceptance do
    Log.info "Running all acceptance tests"
    run_tests('test:acceptance', "acceptance")
  end
end

desc "Perform all tests of given type (default: unit_test)"
task :test, [:type] do |task, args|
  Log.info "Running all tests"

  type = args.type || 'unit'
  Rake::Task["test:#{type}"].invoke()
end

private def run_tests(invoking_task, test_type)
  if ENV['local_dev'] == 'true'
    formatter = "html"
    result_filename = {
      'unit' => "rspec_unit_results.html",
      'acceptance' => "rspec_acceptance_results.html",
    }
  else
    formatter = "RspecJunitFormatter"
    result_filename = {
      'unit' => "rspec_results_in_junit_format.xml",
      'acceptance' => "rspec_acceptance_results_in_junit_format.xml",
    }
  end

  special_tag = "~skip"

  if ENV['bamboo_rspec_parallel'] == 'true'
    require 'parallel_tests'
    file_name, extension = result_filename[test_type].split('.')
    File.open(".rspec_parallel", 'w') { |config_file|
      config_file.puts("--require #{BASE_DIR}/spec/spec_helper")
      config_file.puts("--format progress")
      config_file.puts("--format #{formatter}")
      config_file.puts("--failure-exit-code 0")
      config_file.puts("--out #{file_name}<%= ENV['TEST_ENV_NUMBER'] %>.#{extension}")
    }
    parallel_tests = ParallelTests::CLI.new()
    rspec_opts = " -o '--tag=#{special_tag}' "
    parallel_tests.run("--type test -t rspec #{rspec_opts} #{BASE_DIR}/spec/#{test_type}".split)
  else
    require 'rspec/core/rake_task'

    rspec_rake_options = [
        "-I'#{BASE_DIR}'",
        "-I'#{BASE_DIR}/lib'",
        "-I'#{BASE_DIR}/spec'",
        "--tag #{special_tag}",
        "--format #{formatter}",
        "--out #{result_filename[test_type]}",
        "--failure-exit-code 0",
        "--require #{BASE_DIR}/spec/spec_helper.rb"
    ]

    rspec_rake_task = RSpec::Core::RakeTask.new(invoking_task)
    rspec_rake_task.pattern = "#{BASE_DIR}/spec/#{test_type}/**/*_spec.rb"
    rspec_rake_task.rspec_opts = rspec_rake_options.join(' ')
  end
end
