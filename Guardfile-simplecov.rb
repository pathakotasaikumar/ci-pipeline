# A sample Guardfile
# More info at https://github.com/guard/guard#readme

## Uncomment and set this to only include directories you want to watch
# directories %w(app lib config test spec features) \
#  .select{|d| Dir.exists?(d) ? d : UI.warning("Directory #{d} does not exist")}

## Note: if you are using the `directories` clause above and you are not
## watching the project directory ('.'), then you will want to move
## the Guardfile to a watched dir and symlink it back, e.g.
#
#  $ mkdir config
#  $ mv Guardfile config/
#  $ ln -s config/Guardfile .
#
# and, you'll have to watch "config/Guardfile" instead of "Guardfile"

# guard runs specific unit tests continuously with simplecov report
def execute_ps_test(file_path:)
  puts "Running PowerShell file: #{file_path}"

  cmd = [
    'echo $(pwd)',
    "echo 'Running tests for PowerShell: #{file_path}'",
    "pwsh -c \"Invoke-Pester -Script @{ Path = '#{file_path}'; } -EnableExit \""
  ].join(' && ')

  puts "Running: #{cmd}"
  system('clear && ' + cmd)
end

guard :rspec, cmd: 'rspec' do
  # https://github.com/guard/guard-rspec

  simplecov_enabled = true
  simplecov_coverage = 80

  # global spec config update
  watch('spec/spec_helper.rb') {
    target_cmd = [
      "echo $(pwd)",
      "clear",

      "export bamboo_disable_log_output=true",
      "export bamboo_simplecov_enabled=#{simplecov_enabled}",
      "export bamboo_simplecov_coverage=#{simplecov_coverage}",

      "rspec spec/unit --format documentation"
    ].join(' && ')

    puts "Running: #{target_cmd}"
    system(target_cmd)
  }

  # local dev -> spec file update
  watch(%r{^lib/(.+)\.rb$}) { |m|
    target_spec_file = "spec/unit/#{m[1]}_spec.rb"
    puts "Running spec file: #{target_spec_file}"

    target_cmd = [
      "echo $(pwd)",
      "clear",

      "export bamboo_disable_log_output=true",
      "export bamboo_simplecov_enabled=#{simplecov_enabled}",
      "export bamboo_simplecov_coverage=#{simplecov_coverage}",

      # exporting custom filter for simplecov to scope fimal coverage report to this partocular file
      "export bamboo_simplecov_custom_filters='^(?!\\/#{m[0].gsub('/', '\\/')})'",

      "rspec --pattern #{target_spec_file} --format documentation"
    ].join(' && ')

    puts "Running: #{target_cmd}"
    system(target_cmd)
  }

  # local spec file update
  watch(%r{^spec/(.+)\.rb$}) { |m|
    target_spec_file = "#{m[1]}.rb"

    target_cmd = [
      "echo $(pwd)",
      "clear",

      "export bamboo_disable_log_output=true",
      "export bamboo_simplecov_enabled=#{simplecov_enabled}",
      "export bamboo_simplecov_coverage=#{simplecov_coverage}",

      "export bamboo_simplecov_custom_filters='^(?!\\/#{m[0].gsub('spec/unit', 'lib').gsub('_spec', '').gsub('/', '\\/')})'",

      "rspec --pattern #{target_spec_file} --format documentation"
    ].join(' && ')

    puts "Running: #{target_cmd}"
    system(target_cmd)
  }

  # local .ps1 file update
  watch(%r{^lib/(.+)\.ps1$}) { |m|
    execute_ps_test(
      file_path: "spec_ps/unit/#{m[1]}.Tests.ps1"
    )
  }

  # local .psm1 file update
  watch(%r{^lib/(.+)\.psm1$}) { |m|
    execute_ps_test(
      file_path: "spec_ps/unit/#{m[1]}.Tests.ps1"
    )
  }

  # specs for .ps1 files
  watch(%r{^spec_ps/(.+)\.ps1$}) { |m|
    execute_ps_test(
      file_path: "spec_ps/#{m[1]}.ps1"
    )
  }
end
