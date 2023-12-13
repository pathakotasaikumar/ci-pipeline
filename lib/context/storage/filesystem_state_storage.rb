require 'yaml'
require 'tmpdir'

class FilesystemStateStorage
  def initialize(directory)
    @directory = directory
  end

  def load(context_path)
    context_filepath = "#{Dir.tmpdir}/#{@directory}/#{context_path.join('/')}"
    begin
      context_yaml = File.read(context_filepath)
      variables = YAML.load(context_yaml)
    rescue => e
      Log.warn "Failed to load context from local path #{context_filepath.inspect} - #{e}"
      variables = nil
    end

    return variables
  end

  def save(context_path, variables)
    if !variables.nil?
      begin
        context_filepath = "#{Dir.tmpdir}/#{@directory}/#{context_path.join('/')}"
        FileUtils.mkpath(File.dirname(context_filepath))
        context_yaml = File.write(context_filepath, YAML.dump(variables))
      rescue => e
        Log.warn "Failed to save context from local path #{context_filepath.inspect} - #{e}"
      end
    end
  end
end
