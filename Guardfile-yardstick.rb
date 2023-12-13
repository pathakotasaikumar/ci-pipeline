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

# guard runs specific unit tests continuously with yardstick report
guard :rspec, cmd: 'rspec' do
  # https://github.com/guard/guard-rspec

  # local dev -> spec file update
  watch(%r{^lib/(.+)\.rb$}) { |m|
    target_file = m[0]
    message_string = "Running YardStick against file: #{target_file}"

    options = [
      "#{target_file}"
    ].join(',')

    puts "Running YardStick against fiules: #{options}"

    target_cmd = [
      "echo $(pwd)",
      "clear",
      "echo #{message_string}",
      "which yardstick",

      "export bamboo_pipeline_qa=true",
      "export bamboo_yardstick_path='#{options}'",

      "rake qa:yardstick"
    ].join(' && ')

    puts "Running: #{target_cmd}"
    system(target_cmd)
  }
end
