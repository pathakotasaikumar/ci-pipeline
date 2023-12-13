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

# guard runs specific unit tests continuously
guard :rspec, cmd: 'rspec' do
    
        # https://github.com/guard/guard-rspec
    
        # global spec config update
        watch('spec/spec_helper.rb')  { 
            target_cmd = [    
                "echo $(pwd)",
                "clear",
 
                "rspec spec/unit --format documentation"
            ].join(' && ')
    
            puts "Running: #{target_cmd}"
            system(target_cmd)
        }

        # local dev -> spec file update
        watch(%r{^lib/(.+)\.rb$})     { |m|
            
            target_spec_file = "spec/unit/#{m[1]}_spec.rb"
            puts "Running spec file: #{target_spec_file}"
            target_cmd = [
                "echo $(pwd)",
                "clear",
                "rspec --pattern #{target_spec_file} --format documentation"
            ].join(" && ")
    
            puts "Running: #{target_cmd}"
            system(target_cmd)
        }
    
        # local spec file update
        watch(%r{^spec/(.+)\.rb$})     { |m|
        
            target_spec_file = "#{m[1]}.rb"
            target_cmd = [
                "echo $(pwd)",
                "clear",
                "rspec --pattern #{target_spec_file} --format documentation"
            ].join(' && ')                 
    
            puts "Running: #{target_cmd}"
            system(target_cmd)
        }
       
    end