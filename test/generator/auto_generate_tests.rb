# assumption is one class or module(1 level) per file

BASE_DIR = "../.."
INPUTS_DIR = "/lib/**/*.rb"
Dir.glob("#{BASE_DIR}#{INPUTS_DIR}")
.each{ |file_name_plus_relative_path|
  begin
    file_name_plus_full_path = File.expand_path(file_name_plus_relative_path)
    file_name = File.basename(file_name_plus_full_path)
    file_name_no_extension =  File.basename(file_name_plus_full_path,".*")
    file_path_only = File.dirname(file_name_plus_relative_path)
    class_name ="", module_name=""

    File.open(file_name_plus_full_path).each do |line|

      line = line.strip

      if line.match(/^module/) or line.match(/^class/)

        object = Array.new

        if  line.match(/^module/)
          module_name = line.split(' ',2).last
          object = module_name
        else
          class_name = line.split(' ',2).last.split(' <',2).first
          object = class_name
        end

        File.open(file_name_no_extension+"_spec.rb", "w"){ |file|
        load_path = "$LOAD_PATH.unshift(\""+file_path_only+"\")"
        file.puts load_path.sub(/..\/../,"\#{BASE_DIR}")
        file.puts "require '#{file_name_no_extension}'"
        file.puts
        file.puts "RSpec.describe #{object} ,:skip => true do"
      }
      end

      if line.match(/^def /)

        method_name = line.split(' ',2).last.split('.',2).last
        method_name_only = method_name.split('(',2).first

        identifier = ""
        if(module_name == "")
          identifier = class_name
        else
          identifier = module_name
        end

        File.open(file_name_no_extension+"_spec.rb", "a"){ |file|
        file.puts
        file.puts "  context '.#{method_name_only}' do"
        file.puts "    it 'does something',:skip => true do"
        file.puts "      " + identifier +"."+ method_name
        file.puts "    end"
        file.puts "  end"
        }
      end
    end

    if(class_name!="")
      File.open(file_name_no_extension+"_spec.rb", "a") { |file| file.puts "end #RSpec.describe"}
    end

  end
}
