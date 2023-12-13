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

# guard runs specific unit tests continuously with rubocop report
guard :rspec, cmd: 'rspec' do
  # https://github.com/guard/guard-rspec

  # local dev -> spec file update
  watch(%r{^lib/(.+)\.rb$}) { |m|
    target_file = m[0]
    message_string = "Running Rubocop against file: #{target_file}"

    options = [
      "#{target_file}",
      '-f', 'simple',
      '-f', 'offenses',
      '-f', 'worst',
      '-f', 'html',
      '-o', "logs/rubocop_report_#{target_file}.html",
      '--only', 'Lint'
    ]           .join(' ')

    puts "Running Rubocop with options: #{options}"

    target_cmd = [
      "echo $(pwd)",
      "clear",
      "echo #{message_string}",
      "which rubocop",
      "rubocop #{options}"
    ].join(' && ')

    puts "Running: #{target_cmd}"
    system(target_cmd)
  }
end
