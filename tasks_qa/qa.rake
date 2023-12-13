require 'rake'
require 'rubocop/rake_task'
require 'yardstick/rake/measurement'
require 'yardstick/rake/verify'

namespace :qa do

  yardstick_report = 'logs/yardstick_report.txt'
  yardstick_config = '.yardstick.yaml'
  yardstick_options = YAML.load_file(yardstick_config)

  task :all => ['test', 'qa:rubocop', 'qa:yardstick']

  Yardstick::Rake::Measurement.new(:yardstick_measure) do |ya|
    ya.output = yardstick_report

    file_path = ENV['bamboo_yardstick_path']

    if(!file_path.nil?)
      paths = file_path.split(',')
      Log.info "Running yardstick against paths: #{paths}"
      ya.path = paths
    else
      Log.info "Running yardstick against all codebase"
    end
    
  end

  task :yardstick_report do

    Log.info "Rendering yardstick report:[#{yardstick_report}]"

    File.open(yardstick_report).each do |line|
      # clean up new line char
      Log.info line.strip
    end
  end

  Yardstick::Rake::Verify.new(:yardstick_verify, yardstick_options) do |ya|

    yardstick_threshold = ENV['bamboo_yardstick_threshold'] || 54

    ya.threshold = yardstick_threshold.to_i
    ya.require_exact_threshold = false

    Log.info  "Running Yardstick with threshold: #{yardstick_threshold} and options:"
    Log.info  YAML.dump(yardstick_options)
  end

  task :yardstick do

    Log.info 'Rendering yardstick...'

    Rake::Task['qa:yardstick_measure'].invoke()
    Rake::Task['qa:yardstick_report'].invoke()
    Rake::Task['qa:yardstick_verify'].invoke()
  end

  RuboCop::RakeTask.new(:rubocop) do |task|

    rubocop_only = ENV['bamboo_rubocop_only'] || 'Lint'

    task.options = [
        '-f', 'simple',
        '-f', 'offenses',
        '-f', 'worst',
        '-f', 'html',
        '-o', 'logs/rubocop_report.html',
        '--only', rubocop_only]

    puts "Running Rubocop with options: #{task.options.join(' ')}"

    task.fail_on_error = false
  end

end
